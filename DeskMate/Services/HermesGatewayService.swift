import Foundation

/// Hermes Gateway 进程生命周期管理 — 对齐 Flutter `HermesService` 中
/// `startGateway` / `stopGateway` / `_ensureApiServerKey` / `_waitForGatewayReady`。
///
/// 负责：
/// 1. 在应用启动时拉起 `python -m hermes_cli.main gateway run` 子进程
/// 2. 注入 `.env` 中的 API key 变量到子进程环境
/// 3. 确保 `~/.hermes/.env` 中存在 `API_SERVER_KEY`
/// 4. 轮询 `/health` 端点直到 Gateway 就绪（最长 30s）
/// 5. 应用退出或重启时优雅停止子进程
final class HermesGatewayService {

    /// 单例 —— 全局唯一管理 Gateway 进程。
    static let shared = HermesGatewayService()

    /// 当前运行的 Gateway 子进程（与 Flutter `_gatewayProcess` 等价）。
    private var gatewayProcess: Process?

    /// 当前 API_SERVER_KEY（与 Flutter `_apiServerKey` 等价）。
    private(set) var apiServerKey: String?

    /// 标记 Gateway 是否已就绪（最近一次健康检查通过）。
    private(set) var isReady: Bool = false

    /// 当前 Gateway 启动时使用的 Hermes profile。
    ///
    /// `nil` 表示默认 profile（`~/.hermes`），非 nil 时表示 `~/.hermes/profiles/<name>`。
    /// 用于让 AIChat 等工作区配置写入 Gateway 实际读取的 config.yaml。
    @MainActor
    private(set) var currentProfile: String?

    private init() {}

    // MARK: - Start

    /// 启动 Gateway 进程 — 对齐 Flutter `startGateway`。
    ///
    /// 流程：
    /// 1. 停止旧进程（避免端口冲突）
    /// 2. 读取 `~/.hermes/.env`，注入 API key 变量到子进程环境
    /// 3. 确保 `API_SERVER_KEY` 存在
    /// 4. 启动 `python -m hermes_cli.main gateway run` 子进程
    /// 5. 轮询 `/health`（每 2s 一次，最长 30s）
    ///
    /// - Parameters:
    ///   - profile: 可选 profile 名称（与 Flutter `--profile` 参数一致）。
    ///   - port: Gateway 监听端口，默认 8642。
    /// - Returns: 是否在 30s 内健康检查通过。
    @discardableResult
    func startGateway(profile: String? = nil,
                      port: Int = AppConstants.defaultGatewayPort) async -> Bool {
        NSLog("[HermesGateway] startGateway: 开始, port=\(port)")

        let hermesHome = AppConstants.resolveHermesHome()
        let pythonPath = hermesPython(hermesHome)
        NSLog("[HermesGateway] startGateway: hermesHome=\(hermesHome)")
        NSLog("[HermesGateway] startGateway: pythonPath=\(pythonPath)")

        let fm = FileManager.default
        let pythonExists = fm.fileExists(atPath: pythonPath)
        NSLog("[HermesGateway] startGateway: pythonPath 存在=\(pythonExists)")
        if !pythonExists {
            // 尝试查找系统 python3 作为 fallback
            let whichResult = runShellSync("which python3 2>/dev/null || which python 2>/dev/null")
            NSLog("[HermesGateway] startGateway: 系统 python 查找结果=\(whichResult)")
            NSLog("[HermesGateway] startGateway: Python 路径不存在: \(pythonPath)")
            return false
        }

        // 检查 hermes-agent 目录
        let agentDir = (hermesHome as NSString).appendingPathComponent("hermes-agent")
        let agentExists = fm.fileExists(atPath: agentDir)
        NSLog("[HermesGateway] startGateway: hermes-agent 目录存在=\(agentExists)")

        // 1. 停止旧进程
        NSLog("[HermesGateway] startGateway: 停止旧 Gateway 进程...")
        await stopGateway(port: port)

        // 2. 读取 .env
        let envPath = (hermesHome as NSString).appendingPathComponent(".env")
        var envVarsFromFile: [String: String] = [:]
        if let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) {
            NSLog("[HermesGateway] startGateway: .env 文件内容长度=\(envContent.count)")
            for line in envContent.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let eqIdx = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
                var val = String(trimmed[trimmed.index(after: eqIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                val = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                let masked = val.count > 8 ? "\(val.prefix(8))..." : val
                NSLog("[HermesGateway] startGateway: .env key: \(key)=\(masked)")
                if !val.isEmpty { envVarsFromFile[key] = val }
            }
        } else {
            NSLog("[HermesGateway] startGateway: .env 文件不存在!")
        }

        // 3. 确保 API_SERVER_KEY
        NSLog("[HermesGateway] startGateway: 确保 API_SERVER_KEY...")
        guard let key = ensureApiServerKey(hermesHome: hermesHome) else {
            NSLog("[HermesGateway] startGateway: 无法获取/生成 API_SERVER_KEY")
            return false
        }
        apiServerKey = key
        NSLog("[HermesGateway] startGateway: API_SERVER_KEY 已就绪")

        // 4. 构造启动参数
        var args = ["-m", "hermes_cli.main"]
        if let profile = profile {
            args.append(contentsOf: ["--profile", profile])
        }
        args.append(contentsOf: ["gateway", "run"])
        NSLog("[HermesGateway] startGateway: 启动参数=\(args)")

        // 构造子进程环境
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in envVarsFromFile { environment[k] = v }
        environment["HERMES_HOME"] = hermesHome
        environment["API_SERVER_ENABLED"] = "true"
        environment["API_SERVER_PORT"] = String(port)
        environment["API_SERVER_KEY"] = key
        environment["GATEWAY_ALLOW_ALL_USERS"] = "true"

        NSLog("[HermesGateway] startGateway: 启动 Gateway 进程 (port=\(port))...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = args
        process.currentDirectoryPath = hermesHome
        process.environment = environment

        // 捕获 stderr 到日志文件
        let logDir = (hermesHome as NSString).appendingPathComponent("logs")
        try? fm.createDirectory(atPath: logDir,
                                withIntermediateDirectories: true)
        let logPath = (logDir as NSString)
            .appendingPathComponent("gateway-\(port)-stderr.log")
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil)
        }
        if let stderrHandle = FileHandle(forWritingAtPath: logPath) {
            stderrHandle.seekToEndOfFile()
            process.standardError = stderrHandle
        }

        NSLog("[HermesGateway] startGateway: 调用 process.run()...")
        do {
            try process.run()
        } catch {
            NSLog("[HermesGateway] startGateway: process.run() 抛出异常: \(error)")
            NSLog("[HermesGateway] startGateway: 错误域名=\((error as NSError).domain), 代码=\((error as NSError).code)")
            gatewayProcess = nil
            isReady = false
            return false
        }

        gatewayProcess = process
        NSLog("[HermesGateway] startGateway: Gateway 进程已启动, pid=\(process.processIdentifier), isRunning=\(process.isRunning)")

        // 5. 轮询健康检查
        NSLog("[HermesGateway] startGateway: 开始轮询健康检查...")
        let healthy = await waitForGatewayReady(port: port)
        NSLog("[HermesGateway] startGateway: 健康检查结果=\(healthy)")
        isReady = healthy

        // 6. 启动成功后注入 API key 到共享 GatewayClient，并记录当前 profile
        if healthy, let key = apiServerKey {
            NSLog("[HermesGateway] startGateway: 注入 API key 到 GatewayClient.shared")
            await MainActor.run {
                GatewayClient.shared.setApiKey(key)
                self.currentProfile = profile?.trimmingCharacters(in: .whitespacesAndNewlines)
                NSLog("[HermesGateway] startGateway: currentProfile=\(self.currentProfile ?? "default")")
            }
        }

        return healthy
    }

    // MARK: - Stop

    /// 停止 Gateway 进程 — 对齐 Flutter `stopGateway`。
    ///
    /// 发送 SIGTERM，等待 5s；仍未退出则 SIGKILL；最后等待端口释放（最长 3s）。
    func stopGateway(port: Int = AppConstants.defaultGatewayPort) async {
        guard let process = gatewayProcess else { return }
        DMLogger.log(
            "stopGateway: 正在停止 Gateway 进程 pid=\(process.processIdentifier)",
            name: "HermesGateway"
        )

        // SIGTERM
        kill(process.processIdentifier, SIGTERM)

        // 等待退出（最长 5s）
        let deadline5 = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline5 {
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        }

        if process.isRunning {
            DMLogger.log(
                "stopGateway: Gateway 进程未在5秒内退出，强制 kill",
                name: "HermesGateway"
            )
            kill(process.processIdentifier, SIGKILL)
            // 再等 3s
            let deadline3 = Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline3 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        DMLogger.log(
            "stopGateway: Gateway 进程已退出",
            name: "HermesGateway"
        )
        gatewayProcess = nil
        isReady = false

        // 等待端口释放（最长 3s）
        let deadlinePort = Date().addingTimeInterval(3)
        while Date() < deadlinePort {
            if !isPortInUse(port: port) {
                DMLogger.log(
                    "stopGateway: 端口 \(port) 已释放",
                    name: "HermesGateway"
                )
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }
    }

    // MARK: - Health

    /// 轮询 /health 直到就绪 — 对齐 Flutter `_waitForGatewayReady`。
    ///
    /// 每 2s 检查一次，最长等待 30s；超时后再做一次最终检查。
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

        // 最终检查
        attempt += 1
        NSLog("[HermesGateway] _waitForGatewayReady: 第 \(attempt) 次最终健康检查 (port=\(port))...")
        return await isHealthy(port: port)
    }

    /// 调用 `/health` 端点 — 对齐 Flutter `GatewayClient.isHealthy`。
    func isHealthy(port: Int = AppConstants.defaultGatewayPort) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else {
            return false
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        if let key = apiServerKey {
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

    // MARK: - API_SERVER_KEY

    /// 确保 `~/.hermes/.env` 中存在 `API_SERVER_KEY` — 对齐 Flutter `_ensureApiServerKey`。
    ///
    /// 若已存在非空值则直接返回；否则生成 64 位十六进制随机 key 并追加到 `.env`。
    private func ensureApiServerKey(hermesHome: String) -> String? {
        let envPath = (hermesHome as NSString).appendingPathComponent(".env")

        // 1. 查找现有 key
        if let content = try? String(contentsOfFile: envPath, encoding: .utf8) {
            for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let eqIdx = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: eqIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                if key == "API_SERVER_KEY", !value.isEmpty {
                    DMLogger.log(
                        "_ensureApiServerKey: found existing key",
                        name: "HermesGateway"
                    )
                    return value
                }
            }
        }

        // 2. 生成新 key
        DMLogger.log(
            "_ensureApiServerKey: generating new key",
            name: "HermesGateway"
        )
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        guard status == errSecSuccess else {
            DMLogger.error(
                "_ensureApiServerKey: SecRandomCopyBytes failed: \(status)",
                name: "HermesGateway"
            )
            return nil
        }
        let newKey = bytes.map { String(format: "%02x", $0) }.joined()

        // 3. 确保目录存在
        let fm = FileManager.default
        try? fm.createDirectory(atPath: hermesHome,
                                withIntermediateDirectories: true)

        // 4. 追加到 .env
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
            DMLogger.error(
                "_ensureApiServerKey: 写入 .env 失败: \(error)",
                name: "HermesGateway"
            )
            return nil
        }
    }

    // MARK: - Helpers

    /// 与 Flutter `AppConstants.hermesPython` 一致：
    /// `{hermesHome}/hermes-agent/venv/bin/python`。
    private func hermesPython(_ hermesHome: String) -> String {
        let repoDir = (hermesHome as NSString).appendingPathComponent("hermes-agent")
        let venvDir = (repoDir as NSString).appendingPathComponent("venv")
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
