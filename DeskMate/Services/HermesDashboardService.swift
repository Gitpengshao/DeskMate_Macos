import Foundation

/// Hermes Dashboard 进程生命周期管理。
///
/// 负责在应用启动后拉起 `python -m hermes_cli.main dashboard --no-open`，
/// 默认端口 9119，并通过短轮询确认 Web 服务器已可响应请求。
final class HermesDashboardService {

    /// 全局单例。
    static let shared = HermesDashboardService()

    /// 默认 Dashboard HTTP 端口。
    static let defaultPort: Int = 9119

    /// 当前运行的 Dashboard 进程。
    private var process: Process?

    /// 标记 Dashboard 是否已就绪（可响应 HTTP）。
    private(set) var isReady: Bool = false

    /// 标记是否已尝试启动，避免重复启动。
    private var started: Bool = false

    /// 启动时注入后端的 loopback session token，DashboardClient 用其认证。
    private(set) var sessionToken: String?

    private init() {}

    // MARK: - Public

    /// 启动 Dashboard 子进程并等待其就绪；幂等。
    ///
    /// - Parameter port: 监听端口，默认 9119。
    /// - Returns: 是否成功启动并就绪。
    @discardableResult
    func startDashboard(port: Int = defaultPort) async -> Bool {
        let start = Date()
        NSLog("[HermesDashboard] startDashboard: 进入，port=\(port)，主线程=%@",
              Thread.isMainThread ? "YES" : "NO")
        guard !started else {
            NSLog("[HermesDashboard] startDashboard: 已经尝试启动过，isReady=\(isReady)")
            return isReady
        }
        started = true

        // 若端口仍被占用，清理残留进程；我们必须使用自己生成的 session token，
        // 所以不能直接复用外部启动的 Dashboard。
        let portOccupied = isPortInUse(port: port)
        let alreadyHealthy = await isHealthy(port: port)
        NSLog("[HermesDashboard] startDashboard: portOccupied=\(portOccupied), alreadyHealthy=\(alreadyHealthy)，耗时 %.3fs",
              Date().timeIntervalSince(start))
        if portOccupied || alreadyHealthy {
            let cleanupStart = Date()
            NSLog("[HermesDashboard] startDashboard: 开始清理残留 Dashboard 进程")
            await killOrphanedDashboardProcesses()
            NSLog("[HermesDashboard] startDashboard: 残留进程清理完成，耗时 %.3fs",
                  Date().timeIntervalSince(cleanupStart))
            let waitStart = Date()
            await waitForPortRelease(port: port, maxWait: 5)
            NSLog("[HermesDashboard] startDashboard: 等待端口释放完成，耗时 %.3fs",
                  Date().timeIntervalSince(waitStart))
        }

        let hermesHome = AppConstants.resolveHermesHome(for: nil)
        let hermesBinPath = hermesExecutable(hermesHome)

        let fm = FileManager.default
        let executablePath = hermesBinPath
        if !fm.fileExists(atPath: executablePath) {
            NSLog("[HermesDashboard] startDashboard: 找不到 Hermes 可执行文件: \(executablePath)")
            started = false
            return false
        }

        // 确保 .env 中存在 API_SERVER_KEY（Dashboard 后端与 Gateway 共用）。
        let apiKeyStart = Date()
        guard let apiKey = ensureApiServerKey(hermesHome: hermesHome) else {
            NSLog("[HermesDashboard] startDashboard: 无法获取/生成 API_SERVER_KEY")
            started = false
            return false
        }
        NSLog("[HermesDashboard] startDashboard: API_SERVER_KEY 就绪，耗时 %.3fs",
              Date().timeIntervalSince(apiKeyStart))

        // 生成并固定 loopback session token；DashboardClient 用 Bearer token 访问 /api/*。
        let token = generateSessionToken()
        self.sessionToken = token

        // 桌面应用应启动 headless backend (`hermes serve`)，它是 Dashboard 的 API 后端，
        // 不打开浏览器，也不每次 build Web UI。
        var args = ["serve", "--no-open"]
        if port != HermesDashboardService.defaultPort {
            args.append(contentsOf: ["--port", String(port)])
        }

        var environment = ProcessInfo.processInfo.environment
        environment["HERMES_HOME"] = hermesHome
        environment["API_SERVER_KEY"] = apiKey
        environment["HERMES_DASHBOARD_SESSION_TOKEN"] = token

        let logDir = (hermesHome as NSString).appendingPathComponent("logs")
        try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let logPath = (logDir as NSString).appendingPathComponent("dashboard-\(port).log")
        if !fm.fileExists(atPath: logPath) {
            fm.createFile(atPath: logPath, contents: nil)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        process.currentDirectoryPath = hermesHome
        process.environment = environment

        if let logHandle = FileHandle(forWritingAtPath: logPath) {
            logHandle.seekToEndOfFile()
            // 同时捕获 stdout 与 stderr，便于排查启动失败原因。
            process.standardOutput = logHandle
            process.standardError = logHandle
        }

        NSLog("[HermesDashboard] startDashboard: 启动 Dashboard port=\(port) executable=\(executablePath)")
        do {
            try process.run()
        } catch {
            NSLog("[HermesDashboard] startDashboard: process.run() 失败: \(error)")
            started = false
            return false
        }

        self.process = process

        let readyStart = Date()
        let ready = await waitForDashboardReady(port: port, process: process, logPath: logPath)
        NSLog("[HermesDashboard] startDashboard: waitForDashboardReady 返回 ready=\(ready)，耗时 %.3fs",
              Date().timeIntervalSince(readyStart))
        await MainActor.run { [weak self] in
            self?.isReady = ready
        }

        if !ready {
            let tail = logTail(path: logPath, maxBytes: 4096)
            NSLog("[HermesDashboard] startDashboard: Dashboard 未在预期时间内就绪，日志末尾:\n\(tail)")
            await stopDashboard()
            started = false
        } else {
            NSLog("[HermesDashboard] startDashboard: Dashboard 已就绪")
        }

        NSLog("[HermesDashboard] startDashboard: 总耗时 %.3fs，返回 ready=\(ready)",
              Date().timeIntervalSince(start))
        return ready
    }

    /// 停止 Dashboard 子进程。
    func stopDashboard() async {
        let start = Date()
        NSLog("[HermesDashboard] stopDashboard: 进入，process=%@，主线程=%@",
              process == nil ? "nil" : (process?.isRunning == true ? "running" : "not running"),
              Thread.isMainThread ? "YES" : "NO")
        guard let process = process, process.isRunning else {
            process?.terminate()
            self.process = nil
            await MainActor.run { [weak self] in
                self?.isReady = false
            }
            NSLog("[HermesDashboard] stopDashboard: 无需停止，总耗时 %.3fs", Date().timeIntervalSince(start))
            return
        }

        NSLog("[HermesDashboard] stopDashboard: 停止 Dashboard pid=\(process.processIdentifier)")
        kill(process.processIdentifier, SIGTERM)

        let deadline5 = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline5 {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        if process.isRunning {
            NSLog("[HermesDashboard] stopDashboard: SIGTERM 超时，发送 SIGKILL")
            kill(process.processIdentifier, SIGKILL)
            let deadline3 = Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline3 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        self.process = nil
        await MainActor.run { [weak self] in
            self?.isReady = false
        }
        NSLog("[HermesDashboard] stopDashboard: 完成，总耗时 %.3fs", Date().timeIntervalSince(start))
    }

    /// 探测 Dashboard 是否可响应 HTTP 请求。
    ///
    /// 对 `/health` 发起 GET；若返回任意 HTTP 响应（含 404）均视为服务器已启动。
    func isHealthy(port: Int = defaultPort) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse) != nil else { return false }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Internal

    /// 轮询 Dashboard 健康状态。
    private func waitForDashboardReady(port: Int, process: Process?, logPath: String, maxWait: TimeInterval = 60) async -> Bool {
        let start = Date()
        NSLog("[HermesDashboard] waitForDashboardReady: 进入，maxWait=%.0fs", maxWait)
        let deadline = Date().addingTimeInterval(maxWait)
        var attempt = 0

        while Date() < deadline {
            attempt += 1
            if await isHealthy(port: port) {
                NSLog("[HermesDashboard] waitForDashboardReady: 第 \(attempt) 次健康检查成功，总耗时 %.3fs",
                      Date().timeIntervalSince(start))
                return true
            }
            if let process = process, !process.isRunning {
                let status = process.terminationStatus
                let tail = logTail(path: logPath, maxBytes: 4096)
                NSLog("[HermesDashboard] waitForDashboardReady: Dashboard 进程已退出，exit=\(status)，耗时 %.3fs，日志末尾:\n\(tail)",
                      Date().timeIntervalSince(start))
                return false
            }
            if attempt == 1 || attempt % 5 == 0 {
                NSLog("[HermesDashboard] waitForDashboardReady: 第 \(attempt) 次健康检查未通过，继续等待...")
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        NSLog("[HermesDashboard] waitForDashboardReady: 达到最大等待时间 %.0fs，进行最后一次检查", maxWait)
        let finalReady = await isHealthy(port: port)
        NSLog("[HermesDashboard] waitForDashboardReady: 最终检查结果 ready=\(finalReady)，总耗时 %.3fs",
              Date().timeIntervalSince(start))
        return finalReady
    }

    /// 读取日志文件末尾内容。
    private func logTail(path: String, maxBytes: Int) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { return "<无法读取日志>" }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let offset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "<非 UTF-8 日志>"
    }

    /// 清理系统中残留的 Hermes Dashboard 进程。
    private func killOrphanedDashboardProcesses() async {
        let start = Date()
        NSLog("[HermesDashboard] killOrphanedDashboardProcesses: 进入，主线程=%@",
              Thread.isMainThread ? "YES" : "NO")
        let patterns = [
            "[h]ermes_cli.main.*dashboard",
        ]

        var pids = Set<Int32>()
        for pattern in patterns {
            let psStart = Date()
            let output = await runShell("ps auxww | grep -E '\(pattern)' | awk '{print $2}' || true")
            NSLog("[HermesDashboard] killOrphanedDashboardProcesses: ps pattern='%@' 耗时 %.3fs，输出=%@",
                  pattern, Date().timeIntervalSince(psStart), output.trimmingCharacters(in: .whitespacesAndNewlines))
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let pid = Int32(trimmed), pid > 0 {
                    pids.insert(pid)
                }
            }
        }

        // 同时清理占用默认端口的进程。
        let lsofStart = Date()
        let portOutput = await runShell(
            "lsof -i:\(HermesDashboardService.defaultPort) -P -n | tail -n +2 | awk '{print $2}' || true"
        )
        NSLog("[HermesDashboard] killOrphanedDashboardProcesses: lsof 耗时 %.3fs，输出=%@",
              Date().timeIntervalSince(lsofStart), portOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        for line in portOutput.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let pid = Int32(trimmed), pid > 0 {
                pids.insert(pid)
            }
        }

        guard !pids.isEmpty else {
            NSLog("[HermesDashboard] killOrphanedDashboardProcesses: 未发现残留进程，总耗时 %.3fs",
                  Date().timeIntervalSince(start))
            return
        }
        NSLog("[HermesDashboard] killOrphanedDashboardProcesses: 发现 \(pids.count) 个残留进程: \(pids)")

        let sigtermStart = Date()
        for pid in pids {
            NSLog("[HermesDashboard] killOrphanedDashboardProcesses: 发送 SIGTERM 到 pid=\(pid)")
            kill(pid, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(5)
        var loggedRemaining = false
        while Date() < deadline {
            let remaining = pids.filter { kill($0, 0) == 0 }
            if remaining.isEmpty {
                NSLog("[HermesDashboard] killOrphanedDashboardProcesses: 所有进程已在 SIGTERM 后退出，耗时 %.3fs",
                      Date().timeIntervalSince(sigtermStart))
                break
            }
            if !loggedRemaining {
                NSLog("[HermesDashboard] killOrphanedDashboardProcesses: SIGTERM 等待中，剩余 pid=%@",
                      remaining.description)
                loggedRemaining = true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let remaining = pids.filter { kill($0, 0) == 0 }
        if !remaining.isEmpty {
            let sigkillStart = Date()
            NSLog("[HermesDashboard] killOrphanedDashboardProcesses: SIGTERM 超时，剩余 pid=%@，发送 SIGKILL",
                  remaining.description)
            for pid in remaining {
                kill(pid, SIGKILL)
            }
            let killDeadline = Date().addingTimeInterval(3)
            while Date() < killDeadline {
                let stillAlive = remaining.filter { kill($0, 0) == 0 }
                if stillAlive.isEmpty {
                    NSLog("[HermesDashboard] killOrphanedDashboardProcesses: 所有进程已在 SIGKILL 后退出，耗时 %.3fs",
                          Date().timeIntervalSince(sigkillStart))
                    break
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            let finalRemaining = remaining.filter { kill($0, 0) == 0 }
            if !finalRemaining.isEmpty {
                NSLog("[HermesDashboard] killOrphanedDashboardProcesses: 警告：SIGKILL 后仍有进程存活 pid=%@",
                      finalRemaining.description)
            }
        }

        NSLog("[HermesDashboard] killOrphanedDashboardProcesses: 完成，总耗时 %.3fs，主线程=%@",
              Date().timeIntervalSince(start), Thread.isMainThread ? "YES" : "NO")
    }

    /// 等待端口释放。
    private func waitForPortRelease(port: Int, maxWait: TimeInterval) async {
        let start = Date()
        let deadline = Date().addingTimeInterval(maxWait)
        while Date() < deadline {
            if !isPortInUse(port: port) {
                NSLog("[HermesDashboard] waitForPortRelease: 端口 %d 已释放，耗时 %.3fs", port, Date().timeIntervalSince(start))
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        NSLog("[HermesDashboard] waitForPortRelease: 端口 %d 在 %.0fs 后仍未释放", port, maxWait)
    }

    /// 检查端口是否被占用。
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
        return bindResult != 0
    }

    /// 确保指定 hermesHome 的 `.env` 中存在 `API_SERVER_KEY`。
    ///
    /// 与 HermesGatewayService 逻辑保持一致；若已存在则复用，否则生成并写入。
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
                    return value
                }
            }
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        guard status == errSecSuccess else { return nil }
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
            return nil
        }
    }

    /// Hermes CLI 可执行文件路径：`~/.hermes/hermes-agent/venv/bin/hermes`。
    private func hermesExecutable(_ hermesHome: String) -> String {
        let repoDir = (hermesHome as NSString).appendingPathComponent(AppConstants.hermesAgentDir)
        let venvDir = (repoDir as NSString).appendingPathComponent(AppConstants.hermesVenvDir)
        let binDir = (venvDir as NSString).appendingPathComponent("bin")
        return (binDir as NSString).appendingPathComponent("hermes")
    }

    /// 生成供 loopback 模式使用的 session token（url-safe base64，43 字符）。
    private func generateSessionToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        guard status == errSecSuccess else {
            // 兜底：使用时间戳 + 随机数的 base64 字符串。
            return "\(Date().timeIntervalSince1970)-\(Int.random(in: 0..<Int.max))"
                .data(using: .utf8)!
                .base64EncodedString()
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 异步执行 shell 命令，支持超时终止，避免阻塞当前线程。
    ///
    /// 使用 FileHandle.readabilityHandler 异步累积输出，并在后台线程等待进程退出，
    /// 超过 timeout 后自动 terminate()，防止 `waitUntilExit()` 永远阻塞。
    private func runShell(_ command: String, timeout: TimeInterval = 10) async -> String {
        let start = Date()
        NSLog("[HermesDashboard] runShell: 开始，主线程=%@，cmd=%@，timeout=%.0fs",
              Thread.isMainThread ? "YES" : "NO", command, timeout)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.launchPath = "/bin/bash"
                task.arguments = ["-c", command]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = pipe

                var outputData = Data()
                let outputLock = NSLock()
                let pipeHandle = pipe.fileHandleForReading
                pipeHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    outputLock.lock()
                    if !data.isEmpty {
                        outputData.append(data)
                    }
                    outputLock.unlock()
                }

                do {
                    try task.run()
                } catch {
                    pipeHandle.readabilityHandler = nil
                    NSLog("[HermesDashboard] runShell: 启动失败 error=%@，cmd=%@",
                          String(describing: error), command)
                    continuation.resume(returning: "error: \(error)")
                    return
                }

                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    task.waitUntilExit()
                    group.leave()
                }

                if group.wait(timeout: .now() + timeout) == .timedOut {
                    NSLog("[HermesDashboard] runShell: 超时 %.0fs，终止任务 cmd=%@", timeout, command)
                    task.terminate()
                    _ = group.wait(timeout: .now() + 2)
                }

                pipeHandle.readabilityHandler = nil
                try? pipeHandle.close()

                outputLock.lock()
                let output = String(data: outputData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                outputLock.unlock()

                let elapsed = Date().timeIntervalSince(start)
                NSLog("[HermesDashboard] runShell: 完成，耗时 %.3fs，exit=%d，主线程=%@，输出长度=%d",
                      elapsed, task.terminationStatus, Thread.isMainThread ? "YES" : "NO", output.count)
                continuation.resume(returning: output)
            }
        }
    }
}
