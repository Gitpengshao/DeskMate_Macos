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
    /// 使用 `stopAllGateways()` 确保清理所有残留进程，避免端口占用导致启动失败。
    func restartGateway(for profile: String?) async -> (port: Int, apiKey: String)? {
        let key = registryKey(for: profile)
        let existingPort = await registry.instances[key]?.port

        DMLogger.log(
            "restartGateway: 准备重启 profile=\(profile ?? "default") port=\(existingPort ?? -1)",
            name: "HermesGateway"
        )

        await stopAllGateways()
        return await startGatewayInternal(profile: profile, preferredPort: existingPort)
    }

    /// 停止所有已注册的 Gateway 进程，并清理系统中残留的 Hermes Gateway 进程。
    func stopAllGateways() async {
        let instances = await Array(registry.instances.values)
        await MainActor.run { [weak self] in
            self?.currentProfile = nil
            self?.isReady = false
        }

        for instance in instances {
            DMLogger.log(
                "stopAllGateways: 停止 pid=\(instance.process.processIdentifier) port=\(instance.port)",
                name: "HermesGateway"
            )
            await stopProcess(instance.process, port: instance.port)
        }
        await registry.instances.removeAll()

        // 清理应用崩溃或上次未正常退出时残留的 Hermes Gateway 进程，避免端口被占用。
        await killOrphanedGatewayProcesses()

        // 确保默认端口彻底释放：先等 30 秒（覆盖 TCP TIME_WAIT 周期），若仍被占用则强制 SIGKILL 监听进程。
        // TIME_WAIT 状态下 bind() 会失败但 lsof 看不到 LISTEN 进程，只能等待自然过期。
        await waitForPortRelease(port: AppConstants.defaultGatewayPort, maxWait: 30)
        if isPortInUse(port: AppConstants.defaultGatewayPort) {
            DMLogger.log(
                "stopAllGateways: 端口 \(AppConstants.defaultGatewayPort) 仍未释放，强制清理监听进程",
                name: "HermesGateway"
            )
            await killListenersOnPort(port: AppConstants.defaultGatewayPort)
            await waitForPortRelease(port: AppConstants.defaultGatewayPort, maxWait: 15)
        }
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
    /// 传入 `process` 可在进程已退出时立即停止等待，避免端口未释放时轮询满 30 秒。
    func waitForGatewayReady(port: Int = AppConstants.defaultGatewayPort,
                             process: Process? = nil,
                             maxWait: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(maxWait)
        var attempt = 0

        while Date() < deadline {
            attempt += 1
            NSLog("[HermesGateway] _waitForGatewayReady: 第 \(attempt) 次健康检查 (port=\(port))...")
            if await isHealthy(port: port) {
                NSLog("[HermesGateway] _waitForGatewayReady: 第 \(attempt) 次健康检查成功")
                return true
            }
            // 进程已退出，端口不可能再就绪，立即失败
            if let process = process, !process.isRunning {
                NSLog("[HermesGateway] _waitForGatewayReady: Gateway 进程已退出，停止等待")
                return false
            }
            NSLog("[HermesGateway] _waitForGatewayReady: 第 \(attempt) 次健康检查失败，1s 后重试")
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
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
            // 停止进程后等待端口真正释放，避免新进程因 address already in use 启动失败。
            await waitForPortRelease(port: existing.port, maxWait: 3)
        }

        // 兜底：若目标端口仍被占用（残留进程未被注册或 TIME_WAIT 未过期），强制清理监听进程。
        if isPortInUse(port: port) {
            DMLogger.log(
                "startGatewayInternal: 端口 \(port) 仍被占用，强制清理监听进程",
                name: "HermesGateway"
            )
            await killListenersOnPort(port: port)
            await waitForPortRelease(port: port, maxWait: 15)
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
        // 添加 --replace 以自动替换可能残留的同名 Gateway 实例，避免启动失败。
        var args = ["-m", "hermes_cli.main"]
        if let profile = profile, !profile.isEmpty, profile != "default" {
            args.append(contentsOf: ["--profile", profile])
        }
        args.append(contentsOf: ["gateway", "run", "--replace"])
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
        let healthy = await waitForGatewayReady(port: port, process: process)
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

    /// 清理系统中非当前应用实例启动的残留 Hermes Gateway 进程。
    /// 通过命令行匹配与端口监听两种方式查找，避免残留进程继续占用端口。
    private func killOrphanedGatewayProcesses() async {
        var pids = Set<Int32>()

        // 1. 匹配命令行中包含 hermes gateway 相关字样的进程（排除 grep 自身）。
        //    使用 ps auxww 显示完整命令行，避免 macOS 截断导致匹配失败。
        let patterns = [
            "[h]ermes_cli.main.*gateway",
            "[h]ermes-agent.*gateway",
            "[g]ateway/run.py"
        ]
        for pattern in patterns {
            let cmdOutput = runShellSync(
                "ps auxww | grep -E '\(pattern)' | awk '{print $2}' || true"
            )
            for line in cmdOutput.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let pid = Int32(trimmed), pid > 0 {
                    pids.insert(pid)
                }
            }
        }

        // 2. 查找占用默认 Gateway 端口的进程（不限于 LISTEN 状态，更彻底）。
        let portOutput = runShellSync(
            "lsof -i:\(AppConstants.defaultGatewayPort) -P -n | tail -n +2 | awk '{print $2}' || true"
        )
        for line in portOutput.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let pid = Int32(trimmed), pid > 0 {
                pids.insert(pid)
            }
        }

        guard !pids.isEmpty else { return }

        DMLogger.log(
            "killOrphanedGatewayProcesses: 发现 \(pids.count) 个残留 Gateway 进程: \(pids.sorted())",
            name: "HermesGateway"
        )

        // 发送 SIGTERM。
        for pid in pids {
            DMLogger.log("killOrphanedGatewayProcesses: 发送 SIGTERM 到 pid=\(pid)", name: "HermesGateway")
            kill(pid, SIGTERM)
        }

        let termDeadline = Date().addingTimeInterval(5)
        while Date() < termDeadline {
            let remaining = pids.filter { kill($0, 0) == 0 }
            if remaining.isEmpty { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        // 超时未退出的强制 SIGKILL。
        for pid in pids {
            if kill(pid, 0) == 0 {
                DMLogger.log("killOrphanedGatewayProcesses: pid=\(pid) 未退出，发送 SIGKILL", name: "HermesGateway")
                kill(pid, SIGKILL)
            }
        }

        let killDeadline = Date().addingTimeInterval(3)
        while Date() < killDeadline {
            let remaining = pids.filter { kill($0, 0) == 0 }
            if remaining.isEmpty { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let remaining = pids.filter { kill($0, 0) == 0 }
        if !remaining.isEmpty {
            DMLogger.log("killOrphanedGatewayProcesses: 以下进程未能终止: \(remaining.sorted())", name: "HermesGateway")
        } else {
            DMLogger.log("killOrphanedGatewayProcesses: 所有残留进程已终止", name: "HermesGateway")
        }
    }

    /// 等待指定端口释放。
    private func waitForPortRelease(port: Int, maxWait: TimeInterval) async {
        let deadline = Date().addingTimeInterval(maxWait)
        while Date() < deadline {
            if !isPortInUse(port: port) {
                DMLogger.log("waitForPortRelease: 端口 \(port) 已释放", name: "HermesGateway")
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        DMLogger.log("waitForPortRelease: 端口 \(port) 在 \(maxWait)s 内未释放", name: "HermesGateway")
    }

    /// 通过 lsof 查找监听指定端口的进程并强制 SIGKILL。
    private func killListenersOnPort(port: Int) async {
        let output = runShellSync(
            "lsof -iTCP:\(port) -sTCP:LISTEN -P -n | tail -n +2 | awk '{print $2}' || true"
        )
        var pids = Set<Int32>()
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let pid = Int32(trimmed), pid > 0 {
                pids.insert(pid)
            }
        }
        guard !pids.isEmpty else {
            DMLogger.log("killListenersOnPort: 未找到监听端口 \(port) 的进程", name: "HermesGateway")
            return
        }
        DMLogger.log(
            "killListenersOnPort: 对端口 \(port) 的监听进程发送 SIGKILL: \(pids.sorted())",
            name: "HermesGateway"
        )
        for pid in pids {
            kill(pid, SIGKILL)
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let remaining = pids.filter { kill($0, 0) == 0 }
            if remaining.isEmpty { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
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

    /// 检查端口是否被占用。
    ///
    /// 使用 `bind()` 检测而非 `connect()`，能准确反映 Python 端 `bind()` 是否会成功。
    /// `connect()` 只能检测是否有进程在 LISTEN，无法检测 TIME_WAIT 状态；
    /// 而当旧 Gateway 被 SIGTERM 后，socket 会进入 TIME_WAIT（持续 60-120s），
    /// 此时 `connect()` 返回 ECONNREFUSED（误判为空闲），但 Python `bind()` 会返回
    /// EADDRINUSE，导致 Gateway 启动失败。使用 `bind()` 检测可避免这种误判。
    /// 不设置 SO_REUSEADDR，以模拟 Hermes Python 端 api_server 的 bind 行为。
    private func isPortInUse(port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        // bind 返回 -1 表示端口被占用（包括 LISTEN 与 TIME_WAIT 状态）。
        return bindResult != 0
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
