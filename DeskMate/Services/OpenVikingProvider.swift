import Foundation

/// 外部记忆 Provider 服务（当前仅实现 OpenViking）— 对齐 Flutter 端对应实现。
///
/// 生命周期：
/// 1. 用户点击启用 → `pip install openviking` + 启动服务端
/// 2. 服务以子进程方式运行在 `http://localhost:1933`
/// 3. 禁用 / 退出时通过子进程信号优雅停止
nonisolated final class OpenVikingProvider {

    // MARK: - Constants

    private let defaultEndpoint = "http://localhost:1933"
    private let configRelativePath = ".openviking/ov.conf"
    /// OpenViking 专用 venv 路径（相对 $HOME）。
    /// 用 venv 是为了规避 Homebrew Python 的 PEP 668 限制。
    private let venvRelativePath = ".openviking/venv"

    /// 启动后健康检查的最大等待时间。
    private let startupTimeout: TimeInterval = 30
    /// 健康检查的请求超时。
    private let healthCheckTimeout: TimeInterval = 3
    /// 健康检查间隔。
    private let healthCheckInterval: TimeInterval = 2

    /// 安装超时（pip install openviking）。openviking 包体积较大（带模型），
    /// 留 15 分钟。
    private let installTimeout: TimeInterval = 15 * 60
    /// `openviking-server init` 超时。
    private let initTimeout: TimeInterval = 10 * 60

    /// pip install 用的索引源。默认走清华镜像，国内可达；用户可在 UI 里改回 PyPI。
    private var pipIndexUrl: String = "https://pypi.tuna.tsinghua.edu.cn/simple"

    /// 设置 pip 索引源（URL）。
    func setPipIndexUrl(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pipIndexUrl = trimmed
    }

    /// 当前 pip 索引源。
    var currentPipIndexUrl: String { pipIndexUrl }

    // MARK: - Python interpreter

    /// 用户选定的 Python 解释器绝对路径。
    /// 由 `PythonLocator` 注入；用于所有 `python3` 子进程调用。
    private var pythonPath: String = "/usr/bin/env"

    /// 设置 Python 解释器路径（绝对路径）。供 `init` 或运行期切换。
    func setPythonPath(_ path: String) {
        pythonPath = path
    }

    /// 构造时若 `pythonPath == nil`，调用方应在 `bootstrap` 中通过 `setPythonPath` 注入。
    /// 保留 `nil` 兜底以兼容既有调用方（会使用 `/usr/bin/env python3`）。
    init() {}

    // MARK: - Process handle

    /// 当前运行的 openviking-server 子进程。
    /// 通过类级串行队列保护。
    private var providerProcess: Process?
    private let processLock = NSLock()

    // MARK: - Public API

    /// 最近一次 `install()` 失败的原始 stderr（供 UI 展示）。
    private(set) var lastInstallError: String?

    /// 最近一次 `startServer()` 失败的原始 stderr（供 UI 展示）。
    private(set) var lastStartError: String?

    /// 最近一次 `ensureVenv()` 失败的原始 stderr。
    private(set) var lastVenvError: String?

    // MARK: - Virtual environment (PEP 668)

    /// venv 绝对路径。
    var venvPath: String? {
        guard let home = homeDirectory() else { return nil }
        return "\(home)/\(venvRelativePath)"
    }

    /// venv 内的 Python 解释器绝对路径。
    var venvPythonPath: String? {
        venvPath.map { "\($0)/bin/python3" }
    }

    /// venv 内的 pip 绝对路径。
    var venvPipPath: String? {
        venvPath.map { "\($0)/bin/pip" }
    }

    /// venv 是否已经创建。
    var venvExists: Bool {
        guard let py = venvPythonPath else { return false }
        return FileManager.default.isExecutableFile(atPath: py)
    }

    /// 检查 openviking 包是否已经通过 pip 安装。
    func checkInstalled() async -> Bool {
        // 优先用 venv 检查（venv 已存在时），否则用系统 Python
        let probePython = venvExists ? (venvPythonPath ?? pythonPath) : pythonPath
        do {
            let result = try await runProcess(
                executable: probePython,
                args: ["-c", "import openviking; print(openviking.__file__)"],
                timeout: 15
            )
            if result.exitCode != 0 {
                DMLogger.log(
                    "OpenViking: 未安装 (exit=\(result.exitCode), stderr=\(result.stderr))",
                    name: "OpenVikingProvider"
                )
                return false
            }
            DMLogger.log(
                "OpenViking: 包已安装 @ \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))",
                name: "OpenVikingProvider"
            )
            return true
        } catch {
            DMLogger.error(
                "OpenViking: install check failed: \(error.localizedDescription)",
                name: "OpenVikingProvider"
            )
            return false
        }
    }

    /// 通过 venv + pip 安装 openviking。
    ///
    /// 因为 Homebrew Python 自 PEP 668 起禁止 system-wide pip install，
    /// 必须先在 `~/.openviking/venv/` 下建一个独立 venv，再在 venv 内安装。
    /// - Returns: `true` 安装成功；`false` 安装失败（实际 stderr 见 `lastInstallError`）。
    @discardableResult
    func install(
        progress: ((String) -> Void)? = nil
    ) async -> Bool {
        DMLogger.log("OpenViking.install: entered", name: "OpenVikingProvider")
        // 0. 准备 venv
        progress?("准备 venv ...")
        let venvReady = await ensureVenv()
        DMLogger.log(
            "OpenViking.install: ensureVenv -> \(venvReady)",
            name: "OpenVikingProvider"
        )
        guard venvReady, let py = venvPythonPath else {
            DMLogger.error("OpenViking: venv 未就绪", name: "OpenVikingProvider")
            lastInstallError = """
            虚拟环境创建失败：\(lastVenvError ?? "未知错误")

            解决方式：
            1) 确认所选 Python 解释器可执行 python3 -m venv ...
            2) 如使用 Homebrew Python，可执行 brew install python@3.11 修复
            3) 或在"选择 Python 解释器"中切换到其他 Python
            """
            return false
        }
        DMLogger.log("OpenViking.install: venv python @ \(py)", name: "OpenVikingProvider")
        DMLogger.log(
            "OpenViking.install: venv exists=\(venvExists) index=\(pipIndexUrl)",
            name: "OpenVikingProvider"
        )

        // 先用 venv 的 python 验证 pip 模块本身可调用
        do {
            let probe = try await runProcess(
                executable: py,
                args: ["-m", "pip", "--version"],
                timeout: 15
            )
            DMLogger.log(
                "OpenViking.install: pip probe exit=\(probe.exitCode) " +
                "stdout=\(probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines))",
                name: "OpenVikingProvider"
            )
            if probe.exitCode != 0 {
                lastInstallError = "venv 中 pip 模块不可用：\(probe.stderr)"
                return false
            }
        } catch {
            DMLogger.error(
                "OpenViking.install: pip probe exception: \(error)",
                name: "OpenVikingProvider"
            )
            lastInstallError = "调用 venv pip 失败：\(error.localizedDescription)"
            return false
        }

        progress?("准备 pip 安装 openviking ...")
        DMLogger.log(
            "OpenViking.install: spawning pip install (timeout=\(Int(installTimeout))s) ...",
            name: "OpenVikingProvider"
        )
        do {
            // 使用 `python -m pip` 而不是 venv/bin/pip 脚本，
            // 避免 shebang 解析问题；并显式禁用交互与进度条，
            // 防止在没有 TTY 时 pip 卡住等待输入。
            let result = try await runProcess(
                executable: py,
                args: [
                    "-m", "pip", "install",
                    "--no-input",
                    "--disable-pip-version-check",
                    "--progress-bar", "off",
                    "-i", pipIndexUrl,
                    "--upgrade", "pip", "openviking"
                ],
                timeout: installTimeout,
                onOutput: progress
            )
            DMLogger.log(
                "OpenViking.install: pip install finished exit=\(result.exitCode) " +
                "stderr=\(result.stderr.prefix(200))",
                name: "OpenVikingProvider"
            )
            if result.exitCode != 0 {
                DMLogger.error(
                    "OpenViking: pip install failed: \(result.stderr)",
                    name: "OpenVikingProvider"
                )
                lastInstallError = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return false
            }
            DMLogger.log("OpenViking: pip install OK", name: "OpenVikingProvider")
            lastInstallError = nil
            progress?("pip install 完成")
            return true
        } catch {
            DMLogger.error(
                "OpenViking.install: pip install exception: \(error)",
                name: "OpenVikingProvider"
            )
            lastInstallError = error.localizedDescription
            return false
        }
    }

    /// 创建 OpenViking 专用 venv（如已存在则跳过）。
    /// - Returns: 成功创建或已存在返回 `true`。
    @discardableResult
    func ensureVenv() async -> Bool {
        if venvExists {
            DMLogger.log(
                "OpenViking: venv 已存在 @ \(venvPath ?? "?")",
                name: "OpenVikingProvider"
            )
            return true
        }
        guard let venv = venvPath else {
            lastVenvError = "无法解析 $HOME 路径"
            return false
        }
        do {
            DMLogger.log(
                "OpenViking: 创建 venv @ \(venv) (python=\(pythonPath))",
                name: "OpenVikingProvider"
            )
            // --without-pip：避免某些发行版 pip seed 失败；稍后单独升级 pip
            let result = try await runProcess(
                executable: pythonPath,
                args: ["-m", "venv", venv],
                timeout: 90
            )
            if result.exitCode != 0 {
                DMLogger.error(
                    "OpenViking: venv create failed (exit=\(result.exitCode)): \(result.stderr)",
                    name: "OpenVikingProvider"
                )
                lastVenvError = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return false
            }
            // 用 ensurepip 注入 pip（macOS 系统 Python 上 -m venv 默认不带 pip）
            if let py = venvPythonPath {
                let ensurePip = try await runProcess(
                    executable: py,
                    args: ["-m", "ensurepip", "--upgrade"],
                    timeout: 60
                )
                if ensurePip.exitCode != 0 {
                    DMLogger.error(
                        "OpenViking: ensurepip failed: \(ensurePip.stderr)",
                        name: "OpenVikingProvider"
                    )
                    // 不致命 — 一些 venv 已经有 pip
                }
            }
            DMLogger.log("OpenViking: venv 创建成功", name: "OpenVikingProvider")
            lastVenvError = nil
            return true
        } catch {
            DMLogger.error(
                "OpenViking: venv exception: \(error.localizedDescription)",
                name: "OpenVikingProvider"
            )
            lastVenvError = error.localizedDescription
            return false
        }
    }

    /// 启动 openviking-server 子进程并轮询健康检查。
    /// - Returns: 服务就绪时返回 `true`。
    func startServer() async -> Bool {
        // 1. 确保配置文件存在
        let configReady = await ensureConfigFile()
        if !configReady {
            DMLogger.error(
                "OpenViking: cannot start — config file not ready",
                name: "OpenVikingProvider"
            )
            return false
        }

        // 2. 先杀掉旧进程
        await stopProcess()

        // 解析 openviking-server 完整路径：优先使用当前 Python 解释器 bin 目录下
        // 由 pip 装出的脚本；找不到时回退到 PATH 查找。
        let serverBinary = openVikingServerBinaryPath() ?? "openviking-server"
        DMLogger.log(
            "OpenViking: using server binary @ \(serverBinary)",
            name: "OpenVikingProvider"
        )

        do {
            DMLogger.log("OpenViking: starting server...", name: "OpenVikingProvider")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: serverBinary)
            process.arguments = []

            let stderrPipe = Pipe()
            let stdoutPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = stdoutPipe

            // 用类引用收集 stderr，便于在多线程闭包中安全共享
            let stderrCapture = StreamCapture()
            let stdoutCapture = StreamCapture()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                stderrCapture.append(data)
            }
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                stdoutCapture.append(data)
            }

            try process.run()
            let pid = process.processIdentifier
            DMLogger.log("OpenViking: server started, pid=\(pid)", name: "OpenVikingProvider")

            setProcess(process)

            // 监听非正常退出
            let captureRef = stderrCapture
            process.terminationHandler = { proc in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus != 0 {
                    DMLogger.error(
                        "OpenViking: server exited code=\(proc.terminationStatus) " +
                        "stderr=\(captureRef.snapshot())",
                        name: "OpenVikingProvider"
                    )
                } else {
                    DMLogger.log(
                        "OpenViking: server exited cleanly",
                        name: "OpenVikingProvider"
                    )
                }
            }

            // 3. 轮询健康检查
            lastStartError = nil
            let deadline = Date().addingTimeInterval(startupTimeout)
            var attempt = 0
            while Date() < deadline {
                attempt += 1
                if !process.isRunning {
                    let err = stderrCapture.snapshot()
                    DMLogger.error(
                        "OpenViking: aborting — server process died. stderr=\(err)",
                        name: "OpenVikingProvider"
                    )
                    lastStartError = err.trimmingCharacters(in: .whitespacesAndNewlines)
                    return false
                }
                try? await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
                let running = await checkHealth()
                DMLogger.log(
                    "OpenViking: health check #\(attempt) running=\(running)",
                    name: "OpenVikingProvider"
                )
                if running {
                    DMLogger.log(
                        "OpenViking: server ready (after \(attempt) attempts)",
                        name: "OpenVikingProvider"
                    )
                    lastStartError = nil
                    return true
                }
            }
            let errSnapshot = stderrCapture.snapshot()
            DMLogger.error(
                "OpenViking: server start timed out after \(attempt) attempts. " +
                "stderr=\(errSnapshot)",
                name: "OpenVikingProvider"
            )
            lastStartError = """
            服务在 \(Int(startupTimeout))s 内未响应健康检查。
            可能原因：端口 1933 被占用 / 模型未下载 / 配置异常。
            stderr:
            \(errSnapshot.trimmingCharacters(in: .whitespacesAndNewlines))
            """
            return false
        } catch {
            DMLogger.error(
                "OpenViking: start error: \(error.localizedDescription)",
                name: "OpenVikingProvider"
            )
            lastStartError = error.localizedDescription
            return false
        }
    }

    /// 优雅停止 openviking-server。
    func stopProcess() async {
        let process: Process? = getProcess()
        guard let process = process, process.isRunning else { return }
        let pid = process.processIdentifier
        DMLogger.log("OpenViking: stopping server pid=\(pid)", name: "OpenVikingProvider")
        process.terminate()
        // 等待 5s
        let exited = await waitForExit(process, timeout: 5)
        if !exited {
            DMLogger.log("OpenViking: force killing server", name: "OpenVikingProvider")
            kill(pid, SIGKILL)
            _ = await waitForExit(process, timeout: 3)
        } else {
            DMLogger.log("OpenViking: server stopped", name: "OpenVikingProvider")
        }
        setProcess(nil)
    }

    /// 健康检查：访问 `${endpoint}/health`。
    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(defaultEndpoint)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = healthCheckTimeout
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Config helpers

    /// 确保 `~/.openviking/ov.conf` 存在；不存在时执行 `openviking-server init`。
    func ensureConfigFile() async -> Bool {
        guard let home = homeDirectory() else { return false }
        let configURL = URL(fileURLWithPath: home)
            .appendingPathComponent(configRelativePath)
        if FileManager.default.fileExists(atPath: configURL.path) {
            DMLogger.log(
                "OpenViking: config file found @ \(configURL.path)",
                name: "OpenVikingProvider"
            )
            return true
        }
        let configDir = configURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: configDir.path) {
            do {
                try FileManager.default.createDirectory(
                    at: configDir,
                    withIntermediateDirectories: true
                )
            } catch {
                DMLogger.error(
                    "OpenViking: cannot create config dir: \(error.localizedDescription)",
                    name: "OpenVikingProvider"
                )
                return false
            }
        }

        // 与 Flutter 一致：使用预置输入完成 init 流程
        DMLogger.log(
            "OpenViking: running init — config file not found",
            name: "OpenVikingProvider"
        )
        return await runInitWithStdin()
    }

    /// 通过预置 stdin 运行 `openviking-server init`：
    ///   3      → Ollama (macOS 推荐)
    ///   Enter  → 接受默认（embedding / VLM / query planner / bind）
    ///   Y      → 确认保存
    private func runInitWithStdin() async -> Bool {
        let relPath = configRelativePath
        let serverBinary = openVikingServerBinaryPath() ?? "openviking-server"
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: serverBinary)
            process.arguments = ["init"]
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutCapture = StreamCapture()
            let stderrCapture = StreamCapture()
            stdoutPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if !d.isEmpty { stdoutCapture.append(d) }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if !d.isEmpty { stderrCapture.append(d) }
            }

            process.terminationHandler = { _ in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let configExists = FileManager.default.fileExists(
                    atPath: NSString(string: "~/\(relPath)").expandingTildeInPath
                )
                if configExists {
                    DMLogger.log(
                        "OpenViking: init completed, config created",
                        name: "OpenVikingProvider"
                    )
                    continuation.resume(returning: true)
                } else {
                    DMLogger.error(
                        "OpenViking: init ran but config still missing. " +
                        "stdout=\(stdoutCapture.snapshot()) " +
                        "stderr=\(stderrCapture.snapshot())",
                        name: "OpenVikingProvider"
                    )
                    continuation.resume(returning: false)
                }
            }

            do {
                try process.run()
                // 喂入预设输入：3 (Ollama) + 4 个回车 + 4 个 Y
                let preset = "3\n\nY\n\nY\n\n\nY\n\nY\n"
                if let data = preset.data(using: .utf8) {
                    try stdinPipe.fileHandleForWriting.write(contentsOf: data)
                }
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                DMLogger.error(
                    "OpenViking: init failed to start: \(error.localizedDescription)",
                    name: "OpenVikingProvider"
                )
                continuation.resume(returning: false)
            }

            // 兜底超时
            DispatchQueue.global().asyncAfter(deadline: .now() + initTimeout) {
                if process.isRunning {
                    DMLogger.error(
                        "OpenViking: init timeout, killing",
                        name: "OpenVikingProvider"
                    )
                    process.terminate()
                }
            }
        }
    }

    // MARK: - Hermes config.yaml helpers

    /// 读取 `~/.hermes/config.yaml` 中 `memory.provider` 字段。
    func readConfigMemoryProvider() -> String? {
        let url = URL(fileURLWithPath: AppConstants.hermesPath(AppConstants.hermesConfigFile))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            var inMemory = false
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "memory:" {
                    inMemory = true
                    continue
                }
                if inMemory {
                    let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")
                    if isIndented {
                        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                        if parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespaces) == "provider" {
                            return parts[1].trimmingCharacters(in: .whitespaces)
                        }
                    } else {
                        inMemory = false
                    }
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    /// 写入 `memory.provider` 字段到 `~/.hermes/config.yaml`。
    func writeConfigMemoryProvider(_ provider: String) throws {
        let url = URL(fileURLWithPath: AppConstants.hermesPath(AppConstants.hermesConfigFile))
        var content: String = ""
        if FileManager.default.fileExists(atPath: url.path) {
            content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        // 移除旧的 memory 块
        content = removeYamlBlock(content, key: "memory")

        if provider != "off" {
            var buffer = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !buffer.isEmpty { buffer += "\n" }
            buffer += "memory:\n"
            buffer += "  provider: \(provider)\n"
            content = buffer
        } else {
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
        DMLogger.log(
            "OpenViking: wrote memory.provider=\(provider) to config.yaml",
            name: "OpenVikingProvider"
        )
    }

    /// 移除顶层 YAML 块（key 及其缩进子项）。
    private func removeYamlBlock(_ content: String, key: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        var inBlock = false
        for line in lines {
            let trimmedLeft = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmedLeft.hasPrefix("\(key):") && !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                inBlock = true
                continue
            }
            if inBlock {
                if line.isEmpty || (!line.hasPrefix(" ") && !line.hasPrefix("\t")) {
                    inBlock = false
                    if !line.isEmpty { result.append(line) }
                }
            } else {
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Process helpers

    private func setProcess(_ p: Process?) {
        processLock.lock()
        providerProcess = p
        processLock.unlock()
    }

    private func getProcess() -> Process? {
        processLock.lock()
        defer { processLock.unlock() }
        return providerProcess
    }

    /// 等待进程退出，最长 `timeout` 秒。
    private func waitForExit(_ process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !process.isRunning { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return !process.isRunning
    }

    // MARK: - Subprocess runner (one-shot)

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// 同步执行一次性外部命令，支持超时和实时输出回调。
    ///
    /// 实现要点：
    /// - 不使用 `Pipe.readabilityHandler`（在大输出下会丢数据、且与 `terminationHandler`
    ///   存在死锁风险），改用 `readDataToEndOfFile()` 在后台队列同步读取；
    /// - 进程退出后由 `terminationHandler` 唤醒 continuation；
    /// - 实时输出通过每 0.4s 轮询 buffer 尾部的 `onOutput` 回调推到 UI。
    private func runProcess(
        executable: String,
        args: [String],
        timeout: TimeInterval,
        onOutput: ((String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let argv = ([executable] + args).joined(separator: " ")
        DMLogger.log("runProcess: starting argv=\(argv)", name: "OpenVikingProvider")
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            DMLogger.log("runProcess: pipes created", name: "OpenVikingProvider")

            let stdoutCapture = StreamCapture()
            let stderrCapture = StreamCapture()
            let resumedFlag = ResumeOnceFlag()

            // 节流推送：每 0.4s 一次
            let outputTicker = OutputTicker(interval: 0.4) { [stdoutCapture, stderrCapture] in
                let combined = stdoutCapture.snapshot() + stderrCapture.snapshot()
                let tail = Self.lastNonEmptyLines(in: combined, max: 6)
                onOutput?(tail)
            }
            outputTicker.start()

            // 在后台队列同步读完所有输出（readDataToEndOfFile() 在 EOF 时返回）
            let readQueue = DispatchQueue(label: "ov.runProcess.read", qos: .userInitiated)
            readQueue.async {
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                DMLogger.log(
                    "runProcess: read drained out=\(outData.count)B err=\(errData.count)B",
                    name: "OpenVikingProvider"
                )
                if !outData.isEmpty { stdoutCapture.append(outData) }
                if !errData.isEmpty { stderrCapture.append(errData) }
                outputTicker.stop()
            }
            DMLogger.log("runProcess: read queue scheduled", name: "OpenVikingProvider")

            process.terminationHandler = { proc in
                DMLogger.log(
                    "runProcess: terminationHandler fired exit=\(proc.terminationStatus)",
                    name: "OpenVikingProvider"
                )
                outputTicker.stop()
                // 给 readQueue 一点时间把剩余数据读完（readDataToEndOfFile 阻塞在 EOF）
                readQueue.async {
                    // 最多再等 0.5s 收尾
                    let deadline = Date().addingTimeInterval(0.5)
                    while Date() < deadline,
                          !outPipe.fileHandleForReading.availableData.isEmpty {
                        Thread.sleep(forTimeInterval: 0.02)
                    }
                    if resumedFlag.tryResume() {
                        let finalOut = stdoutCapture.snapshot()
                        let finalErr = stderrCapture.snapshot()
                        let tail = Self.lastNonEmptyLines(
                            in: finalOut + finalErr,
                            max: 6
                        )
                        onOutput?(tail)
                        DMLogger.log(
                            "runProcess: returning exit=\(proc.terminationStatus) " +
                            "out=\(finalOut.count)B err=\(finalErr.count)B",
                            name: "OpenVikingProvider"
                        )
                        continuation.resume(returning: ProcessResult(
                            exitCode: proc.terminationStatus,
                            stdout: finalOut,
                            stderr: finalErr
                        ))
                    }
                }
            }

            do {
                try process.run()
                DMLogger.log(
                    "runProcess: process started pid=\(process.processIdentifier) argv=\(argv)",
                    name: "OpenVikingProvider"
                )
            } catch {
                DMLogger.error(
                    "runProcess: process.run() threw: \(error)",
                    name: "OpenVikingProvider"
                )
                outputTicker.stop()
                if resumedFlag.tryResume() {
                    continuation.resume(throwing: error)
                }
                return
            }

            // 心跳：每 5 秒打一条"还在跑"日志，防止用户怀疑卡死
            let heartbeatQueue = DispatchQueue.global()
            let startTime = Date()
            func scheduleHeartbeat() {
                heartbeatQueue.asyncAfter(deadline: .now() + 5) {
                    if resumedFlag.isResumed { return }
                    let elapsed = Int(Date().timeIntervalSince(startTime))
                    let outLen = stdoutCapture.snapshot().count
                    let errLen = stderrCapture.snapshot().count
                    let tail = Self.lastNonEmptyLines(
                        in: stdoutCapture.snapshot() + stderrCapture.snapshot(),
                        max: 3
                    )
                    DMLogger.log(
                        "runProcess: heartbeat t=\(elapsed)s pid=\(process.processIdentifier) " +
                        "running=\(process.isRunning) out=\(outLen)B err=\(errLen)B tail=\(tail)",
                        name: "OpenVikingProvider"
                    )
                    if process.isRunning {
                        scheduleHeartbeat()
                    }
                }
            }
            scheduleHeartbeat()

            // 超时强制终止
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    DMLogger.error(
                        "runProcess: timeout (>\(Int(timeout))s) — terminating. argv=\(argv)",
                        name: "OpenVikingProvider"
                    )
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            DMLogger.error(
                                "runProcess: SIGKILL pid=\(process.processIdentifier)",
                                name: "OpenVikingProvider"
                            )
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        }
    }

    /// 取出字符串末尾若干非空行（用于 UI 实时进度展示）。
    private static func lastNonEmptyLines(in s: String, max: Int) -> String {
        let lines = s.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return "" }
        let tail = lines.suffix(max)
        return tail.joined(separator: "\n")
    }

    // MARK: - Misc

    /// 解析 `openviking-server` 可执行文件绝对路径。
    /// 优先在 venv 的 bin 目录里找（pip 装出的脚本），
    /// 其次是当前 Python 解释器所在 bin 目录，
    /// 再其次是 `PATH` 扫描；找不到时返回 `nil` 让调用方回退到裸名。
    private func openVikingServerBinaryPath() -> String? {
        // 1) venv 优先
        if let venvBin = venvPath.map({ "\($0)/bin/openviking-server" }),
           FileManager.default.isExecutableFile(atPath: venvBin) {
            return venvBin
        }
        // 2) 当前 Python 的 bin 目录
        if pythonPath != "/usr/bin/env" {
            let binDir = (pythonPath as NSString).deletingLastPathComponent
            let candidate = "\(binDir)/openviking-server"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        // 3) PATH 扫描
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/openviking-server"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func homeDirectory() -> String? {
        if let env = ProcessInfo.processInfo.environment["HOME"], !env.isEmpty {
            return env
        }
        let user = ProcessInfo.processInfo.environment["USER"] ?? ""
        if !user.isEmpty { return "/Users/\(user)" }
        return nil
    }
}

/// 线程安全的流数据收集器（用于 stdout/stderr 缓冲）。
final class StreamCapture: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        let copy = data
        lock.unlock()
        return String(data: copy, encoding: .utf8) ?? ""
    }
}

/// 线程安全的"只 resume 一次"标志 — 防止 Process terminationHandler
/// 在超时被同时触发时对同一个 continuation 多次 resume。
final class ResumeOnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    /// 当前是否已 resume。
    var isResumed: Bool {
        lock.lock(); defer { lock.unlock() }
        return done
    }
    /// 尝试标记为已 resume。返回 `true` 表示本次调用获得了"resume 权"。
    func tryResume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// 节流定时器：按指定间隔重复调用 callback，直到 `stop()`。
final class OutputTicker: @unchecked Sendable {
    private let interval: TimeInterval
    private let callback: () -> Void
    private let lock = NSLock()
    private var stopped = false
    private let queue = DispatchQueue(label: "ov.runProcess.ticker", qos: .utility)

    init(interval: TimeInterval, callback: @escaping () -> Void) {
        self.interval = interval
        self.callback = callback
    }

    func start() {
        scheduleNext()
    }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
    }

    private func scheduleNext() {
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shouldStop = self.stopped
            self.lock.unlock()
            if shouldStop { return }
            self.callback()
            self.scheduleNext()
        }
    }
}
