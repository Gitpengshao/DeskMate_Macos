import Foundation

/// Hermes Gateway 进程生命周期管理 — 支持按 profile 的多进程注册表。
///
/// 负责：
/// 1. 在应用启动时拉起 `python -m hermes_cli.main gateway run` 子进程
/// 2. 默认 profile（`nil` / `default`）固定使用端口 8642
/// 3. 其它 profile 动态分配独立端口（从 8643 开始扫描可用端口）
/// 4. 注入 profile 目录下 `.env` 中的 API key 变量到子进程环境
/// 5. 确保每个 profile 目录下的 `.env` 中存在 `API_SERVER_KEY`
/// 6. 轮询 `/health` 端点直到 Gateway 就绪（最长 30s）
/// 7. 应用退出或重启时优雅停止子进程
final class HermesGatewayService {

    /// 单例 —— 全局唯一管理 Gateway 进程。
    static let shared = HermesGatewayService()

    /// 当前运行的 Gateway 实例注册表，key 为 profile 的规范化值（"" 表示 default）。
    private actor Registry {
        var instances: [String: GatewayInstance] = [:]
    }
    private let registry = Registry()

    /// 当前 API_SERVER_KEY（默认 profile 启动时写入，兼容旧代码）。
    private(set) var apiServerKey: String?

    /// 标记默认 Gateway 是否已就绪（兼容旧代码）。
    private(set) var isReady: Bool = false

    /// 当前 Gateway 启动时使用的 Hermes profile（兼容旧代码，仅记录默认 profile）。
    @MainActor
    private(set) var currentProfile: String?

    private init() {}

    // MARK: - Multi-process API

    /// 确保指定 profile 的 Gateway 正在运行；若未运行则启动，若已在运行则直接返回端口与 key。
    ///
    /// - Parameter profile: `nil` / `"default"` 表示默认 profile，其它为智能体 profile id。
    /// - Returns: 运行成功时返回 `(port, apiKey)`，失败返回 `nil`。
    func ensureGatewayRunning(for profile: String?) async -> (port: Int, apiKey: String)? {
        let key = registryKey(for: profile)
        if let instance = await registry.instances[key], instance.process.isRunning {
            return (instance.port, instance.apiKey)
        }
        return await startGatewayInternal(profile: profile)
    }

    /// 停止指定 profile 的 Gateway。
    func stopGateway(for profile: String?) async {
        let key = registryKey(for: profile)
        guard let instance = await registry.instances[key] else { return }

        DMLogger.log(
            "stopGateway(for:): 正在停止 Gateway 进程 pid=\(instance.process.processIdentifier) port=\(instance.port)",
            name: "HermesGateway"
        )
        await stopProcess(instance.process, port: instance.port)
        await registry.instances.removeValue(forKey: key)

        await MainActor.run { [weak self] in
            if self?.currentProfile == profile { self?.currentProfile = nil }
        }
    }

    /// 重启指定 profile 的 Gateway，保持原有端口不变。
    ///
    /// 用于 `terminal.cwd` 等配置变更后让 Hermes 立即重新读取 config.yaml。
    func restartGateway(for profile: String?) async -> (port: Int, apiKey: String)? {
        let key = registryKey(for: profile)
        let existingPort = await registry.instances[key]?.port

        DMLogger.log(
            "restartGateway: 准备重启 profile=\(profile ?? "default") port=\(existingPort ?? -1)",
            name: "HermesGateway"
        )

        await stopGateway(for: profile)
        return await startGatewayInternal(profile: profile, preferredPort: existingPort)
    }

    /// 停止所有已注册的 Gateway 进程。
    func stopAllGateways() async {
        let instances = await Array(registry.instances.values)
        await MainActor.run { [weak self] in
            self?.currentProfile = nil
        }

        for instance in instances {
            DMLogger.log(
                "stopAllGateways: 停止 pid=\(instance.process.processIdentifier) port=\(instance.port)",
                name: "HermesGateway"
            )
            await stopProcess(instance.process, port: instance.port)
        }
        await registry.instances.removeAll()
    }

    /// 指定 profile 的 Gateway 是否处于就绪状态。
    func isRunning(profile: String?) async -> Bool {
        let key = registryKey(for: profile)
        guard let instance = await registry.instances[key] else { return false }
        return instance.isReady && instance.process.isRunning
    }

    /// 构造对应 profile 的 `GatewayClient`（仅当 Gateway 已就绪时返回非 nil）。
    func client(for profile: String?) async -> GatewayClient? {
        let key = registryKey(for: profile)
        guard let instance = await registry.instances[key], instance.isReady else { return nil }
        return GatewayClient(host: "127.0.0.1", port: instance.port, apiKey: instance.apiKey)
    }

    // MARK: - Compatibility API

    /// 启动 Gateway 进程 — 对齐旧签名，供默认 profile / 旧调用点使用。
    ///
    /// 非默认 profile 且未指定端口时，内部会走动态端口分配。
    @discardableResult
    func startGateway(profile: String? = nil,
                      port: Int = AppConstants.defaultGatewayPort) async -> Bool {
        let result = await startGatewayInternal(profile: profile, preferredPort: port)
        return result != nil
    }

    /// 停止指定端口的 Gateway — 兼容旧签名。
    func stopGateway(port: Int = AppConstants.defaultGatewayPort) async {
        let instances = await Array(registry.instances.values)
        guard let instance = instances.first(where: { $0.port == port }) else { return }

        DMLogger.log(
            "stopGateway(port:): 正在停止 Gateway 进程 pid=\(instance.process.processIdentifier) port=\(port)",
            name: "HermesGateway"
        )
        await stopProcess(instance.process, port: port)
        await registry.instances.removeValue(forKey: registryKey(for: instance.profile))

        await MainActor.run { [weak self] in
            if self?.currentProfile == instance.profile { self?.currentProfile = nil }
        }
    }

    // MARK: - Health

    /// 调用 `/health` 端点 — 对齐 Flutter `GatewayClient.isHealthy`。
    func isHealthy(port: Int = AppConstants.defaultGatewayPort) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else {
            return false
        }
        let instance = await instanceFor(port: port)
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        if let key = instance?.apiKey {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                return (200..<300).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    /// 轮询 /health 直到就绪 — 对齐 Flutter `_waitForGatewayReady`。
    func waitForGatewayReady(port: Int = AppConstants.defaultGatewayPort,
                             maxWait: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(maxWait)
        var attempt = 0

        while Date() < deadline {
            attempt += 1
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            NSLog("[HermesGateway] _waitForGatewayReady: 第 \(attempt) 次健康检查 (port=\(port))...")
            if await isHealthy(port: port) {
                NSLog("[HermesGateway] _waitForGatewayReady: 第 \(attempt) 次健康检查成功")
                return true
            }
            NSLog("[HermesGateway] _waitForGatewayReady: 第 \(attempt) 次健康检查失败")
        }

        attempt += 1
        NSLog("[HermesGateway] _waitForGatewayReady: 第 \(attempt) 次最终健康检查 (port=\(port))...")
        return await isHealthy(port: port)
    }

    // MARK: - Internal implementation

    /// 实际启动逻辑。
    private func startGatewayInternal(profile: String? = nil,
                                      preferredPort: Int? = nil) async -> (port: Int, apiKey: String)? {
        let key = registryKey(for: profile)
        let hermesHome = AppConstants.resolveHermesHome(for: profile)
        let pythonPath = hermesPython(hermesHome)

        NSLog("[HermesGateway] startGatewayInternal: profile=\(profile ?? "default") hermesHome=\(hermesHome)")
        NSLog("[HermesGateway] startGatewayInternal: pythonPath=\(pythonPath)")

        let fm = FileManager.default
        let pythonExists = fm.fileExists(atPath: pythonPath)
        NSLog("[HermesGateway] startGatewayInternal: pythonPath 存在=\(pythonExists)")
        if !pythonExists {
            let whichResult = runShellSync("which python3 2>/dev/null || which python 2>/dev/null")
            NSLog("[HermesGateway] startGatewayInternal: 系统 python 查找结果=\(whichResult)")
            NSLog("[HermesGateway] startGatewayInternal: Python 路径不存在: \(pythonPath)")
            return nil
        }

        // 端口决策：兼容调用指定了端口；未指定时 default 用 8642，其它动态扫描。
        let port: Int
        if let preferred = preferredPort {
            port = preferred
        } else if key.isEmpty {
            port = AppConstants.defaultGatewayPort
        } else {
            port = findAvailablePort(startingAt: AppConstants.defaultGatewayPort + 1, maxPort: 8700)
        }
        NSLog("[HermesGateway] startGatewayInternal: 使用 port=\(port)")

        // 若该 profile 已有实例，先停止。
        if let existing = await registry.instances[key] {
            DMLogger.log(
                "startGatewayInternal: 发现已有实例，先停止 pid=\(existing.process.processIdentifier)",
                name: "HermesGateway"
            )
            await stopProcess(existing.process, port: existing.port)
            await registry.instances.removeValue(forKey: key)
        }

        // 读取 profile 目录下的 .env
        let envPath = (hermesHome as NSString).appendingPathComponent(".env")
        var envVarsFromFile: [String: String] = [:]
        if let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) {
            NSLog("[HermesGateway] startGatewayInternal: .env 文件内容长度=\(envContent.count)")
            for line in envContent.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let eqIdx = trimmed.firstIndex(of: "=") else { continue }
                let k = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
                var v = String(trimmed[trimmed.index(after: eqIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                let masked = v.count > 8 ? "\(v.prefix(8))..." : v
                NSLog("[HermesGateway] startGatewayInternal: .env key: \(k)=\(masked)")
                if !v.isEmpty { envVarsFromFile[k] = v }
            }
        } else {
            NSLog("[HermesGateway] startGatewayInternal: .env 文件不存在!")
        }

        // 确保 API_SERVER_KEY
        NSLog("[HermesGateway] startGatewayInternal: 确保 API_SERVER_KEY...")
        guard let keyValue = ensureApiServerKey(hermesHome: hermesHome) else {
            NSLog("[HermesGateway] startGatewayInternal: 无法获取/生成 API_SERVER_KEY")
            return nil
        }
        NSLog("[HermesGateway] startGatewayInternal: API_SERVER_KEY 已就绪")

        // 构造启动参数
        // 注意：hermes gateway run 不支持 --port 参数，端口通过 API_SERVER_PORT 环境变量控制。
        var args = ["-m", "hermes_cli.main"]
        if let profile = profile, !profile.isEmpty, profile != "default" {
            args.append(contentsOf: ["--profile", profile])
        }
        args.append(contentsOf: ["gateway", "run"])
        NSLog("[HermesGateway] startGatewayInternal: 启动参数=\(args)")

        // 构造子进程环境
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in envVarsFromFile { environment[k] = v }
        environment["HERMES_HOME"] = hermesHome
        environment["API_SERVER_ENABLED"] = "true"
        environment["API_SERVER_PORT"] = String(port)
        environment["API_SERVER_KEY"] = keyValue
        environment["GATEWAY_ALLOW_ALL_USERS"] = "true"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = args
        process.currentDirectoryPath = hermesHome
        process.environment = environment

        // 捕获 stderr 到日志文件
        let logDir = (hermesHome as NSString).appendingPathComponent("logs")
        try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let logPath = (logDir as NSString)
            .appendingPathComponent("gateway-\(port)-stderr.log")
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil)
        }
        if let stderrHandle = FileHandle(forWritingAtPath: logPath) {
            stderrHandle.seekToEndOfFile()
            process.standardError = stderrHandle
        }

        NSLog("[HermesGateway] startGatewayInternal: 调用 process.run()...")
        do {
            try process.run()
        } catch {
            NSLog("[HermesGateway] startGatewayInternal: process.run() 抛出异常: \(error)")
            return nil
        }

        NSLog("[HermesGateway] startGatewayInternal: Gateway 进程已启动, pid=\(process.processIdentifier), isRunning=\(process.isRunning)")

        // 轮询健康检查
        NSLog("[HermesGateway] startGatewayInternal: 开始轮询健康检查...")
        let healthy = await waitForGatewayReady(port: port)
        NSLog("[HermesGateway] startGatewayInternal: 健康检查结果=\(healthy)")

        if healthy {
            let instance = GatewayInstance(
                process: process,
                port: port,
                apiKey: keyValue,
                profile: profile,
                isReady: true
            )
            await registry.instances.updateValue(instance, forKey: key)

            await MainActor.run { [weak self] in
                self?.apiServerKey = keyValue
                if key.isEmpty {
                    GatewayClient.shared.setApiKey(keyValue)
                    self?.currentProfile = profile?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.isReady = true
                }
            }
            return (port, keyValue)
        } else {
            await stopProcess(process, port: port)
            return nil
        }
    }

    /// 停止单个进程并等待端口释放。
    private func stopProcess(_ process: Process, port: Int) async {
        guard process.isRunning else { return }

        kill(process.processIdentifier, SIGTERM)

        let deadline5 = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline5 {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        if process.isRunning {
            DMLogger.log(
                "stopProcess: Gateway 未在5秒内退出，强制 kill",
                name: "HermesGateway"
            )
            kill(process.processIdentifier, SIGKILL)
            let deadline3 = Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline3 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        let deadlinePort = Date().addingTimeInterval(3)
        while Date() < deadlinePort {
            if !isPortInUse(port: port) {
                DMLogger.log("stopProcess: 端口 \(port) 已释放", name: "HermesGateway")
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// 根据端口查找已注册实例。
    private func instanceFor(port: Int) async -> GatewayInstance? {
        await registry.instances.values.first(where: { $0.port == port })
    }

    /// 规范化注册表 key。
    private func registryKey(for profile: String?) -> String {
        let normalized = profile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty || normalized == "default" ? "" : normalized
    }

    /// 扫描可用端口。
    private func findAvailablePort(startingAt: Int, maxPort: Int) -> Int {
        for port in startingAt...maxPort {
            if !isPortInUse(port: port) {
                return port
            }
        }
        return maxPort
    }

    // MARK: - API_SERVER_KEY

    /// 确保指定 hermesHome 的 `.env` 中存在 `API_SERVER_KEY`。
    private func ensureApiServerKey(hermesHome: String) -> String? {
        let envPath = (hermesHome as NSString).appendingPathComponent(".env")

        if let content = try? String(contentsOfFile: envPath, encoding: .utf8) {
            for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let eqIdx = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: eqIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                if key == "API_SERVER_KEY", !value.isEmpty {
                    DMLogger.log("_ensureApiServerKey: found existing key", name: "HermesGateway")
                    return value
                }
            }
        }

        DMLogger.log("_ensureApiServerKey: generating new key", name: "HermesGateway")
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        guard status == errSecSuccess else {
            DMLogger.error("_ensureApiServerKey: SecRandomCopyBytes failed: \(status)", name: "HermesGateway")
            return nil
        }
        let newKey = bytes.map { String(format: "%02x", $0) }.joined()

        let fm = FileManager.default
        try? fm.createDirectory(atPath: hermesHome, withIntermediateDirectories: true)

        let existing = (try? String(contentsOfFile: envPath, encoding: .utf8)) ?? ""
        var newContent = existing
        if !newContent.isEmpty && !newContent.hasSuffix("\n") {
            newContent.append("\n")
        }
        newContent.append("API_SERVER_KEY=\(newKey)\n")

        do {
            try newContent.write(toFile: envPath, atomically: true, encoding: .utf8)
            return newKey
        } catch {
            DMLogger.error("_ensureApiServerKey: 写入 .env 失败: \(error)", name: "HermesGateway")
            return nil
        }
    }

    // MARK: - Helpers

    /// 与 Flutter `AppConstants.hermesPython` 一致：
    /// `{hermesHome}/{hermesAgentDir}/{hermesVenvDir}/bin/python`。
    private func hermesPython(_ hermesHome: String) -> String {
        let repoDir = (hermesHome as NSString).appendingPathComponent(AppConstants.hermesAgentDir)
        let venvDir = (repoDir as NSString).appendingPathComponent(AppConstants.hermesVenvDir)
        let binDir = (venvDir as NSString).appendingPathComponent("bin")
        return (binDir as NSString).appendingPathComponent("python")
    }

    /// 检查端口是否被占用（TCP 连接成功即视为占用）。
    private func isPortInUse(port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    /// 同步执行 shell 命令并返回输出（用于诊断信息）。
    private func runShellSync(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return "error: \(error)"
        }
    }
}

// MARK: - GatewayInstance

private struct GatewayInstance {
    let process: Process
    let port: Int
    let apiKey: String
    let profile: String?
    let isReady: Bool
}
