import Foundation

/// 支持交互式 stdin 写入 + 实时 stdout/stderr 流式输出的进程运行器。
///
/// 与 `StreamingProcessRunner` 的区别：
/// - `StreamingProcessRunner` 只捕获单向输出，不支持 stdin，适合 `pip install` 等非交互命令。
/// - `InteractiveProcessRunner` 支持 `send(_:)` 向 stdin 写入，适合 `hermes gateway setup`
///   这类需要用户在运行时响应提示（选择平台、输入凭据、扫码确认）的交互式命令。
///
/// 使用 `readabilityHandler` 增量捕获输出（而非 `readDataToEndOfFile`），以便实时显示
/// ASCII 二维码。输出通过 `onOutput` 回调推送，调用方应在 `@MainActor` 上更新 UI。
final class InteractiveProcessRunner {

    /// 输出回调类型 — 推送累积的完整输出快照（非增量），调用方直接覆盖显示。
    typealias OutputHandler = (String) -> Void
    /// 进程退出回调 — exitCode 为进程退出码。
    typealias ExitHandler = (Int32) -> Void

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private let outputQueue = DispatchQueue(label: "interactive-runner.output", qos: .userInitiated)
    private var lastSnapshotLen: Int = 0

    private var onOutput: OutputHandler?
    private var onExit: ExitHandler?
    private var hasTerminated: Bool = false

    /// 启动交互式进程。
    ///
    /// - Parameters:
    ///   - executable: 可执行文件路径（如 python）。
    ///   - args: 参数列表。
    ///   - environment: 子进程环境变量；nil 时继承当前进程。
    ///   - currentDirectory: 工作目录；nil 时不设置。
    ///   - onOutput: 输出回调（在后台队列触发，调用方需自行切主线程更新 UI）。
    ///   - onExit: 进程退出回调。
    /// - Returns: 是否成功启动。
    @discardableResult
    func start(
        executable: String,
        args: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil,
        onOutput: @escaping OutputHandler,
        onExit: @escaping ExitHandler
    ) -> Bool {
        self.onOutput = onOutput
        self.onExit = onExit

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = environment ?? ProcessInfo.processInfo.environment
        if let cwd = currentDirectory, !cwd.isEmpty {
            process.currentDirectoryPath = cwd
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        // 增量捕获 stdout / stderr
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.appendOutput(data: data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.appendOutput(data: data)
        }

        process.terminationHandler = { [weak self] proc in
            guard let self = self else { return }
            // 排空管道残余数据
            if let stdout = self.stdoutPipe?.fileHandleForReading {
                stdout.readabilityHandler = nil
                let rest = stdout.readDataToEndOfFile()
                if !rest.isEmpty { self.appendOutput(data: rest) }
            }
            if let stderr = self.stderrPipe?.fileHandleForReading {
                stderr.readabilityHandler = nil
                let rest = stderr.readDataToEndOfFile()
                if !rest.isEmpty { self.appendOutput(data: rest) }
            }
            self.flushSnapshot(force: true)
            self.markTerminated(exitCode: proc.terminationStatus)
        }

        do {
            try process.run()
            DMLogger.log("InteractiveProcessRunner: started \(executable) \(args.joined(separator: " "))", name: "InteractiveProcessRunner")
            return true
        } catch {
            DMLogger.error("InteractiveProcessRunner: failed to start: \(error.localizedDescription)", name: "InteractiveProcessRunner")
            // 推送错误信息到输出
            let errMsg = "启动失败: \(error.localizedDescription)\n"
            appendOutput(data: Data(errMsg.utf8))
            flushSnapshot(force: true)
            markTerminated(exitCode: -1)
            return false
        }
    }

    /// 向子进程 stdin 发送一行输入（自动补换行）。
    func send(_ text: String) {
        guard let handle = stdinPipe?.fileHandleForWriting else { return }
        let line = text.hasSuffix("\n") ? text : text + "\n"
        do {
            try handle.write(contentsOf: Data(line.utf8))
            // 回显到输出区，便于用户看到自己输入了什么
            appendOutput(data: Data(("[输入] " + line).utf8))
            flushSnapshot(force: true)
        } catch {
            DMLogger.error("InteractiveProcessRunner: send failed: \(error.localizedDescription)", name: "InteractiveProcessRunner")
        }
    }

    /// 终止子进程（SIGTERM）。
    func terminate() {
        guard let process = process, process.isRunning else {
            markTerminated(exitCode: -1)
            return
        }
        DMLogger.log("InteractiveProcessRunner: terminating", name: "InteractiveProcessRunner")
        process.terminate()
    }

    /// 进程是否仍在运行。
    var isRunning: Bool {
        process?.isRunning ?? false
    }

    // MARK: - Private

    private func appendOutput(data: Data) {
        outputQueue.async {
            // 合并到 stdoutBuffer（同时存放 stdout 和 stderr 内容，按到达顺序）
            self.stdoutBuffer.append(data)
            self.flushSnapshotInternal()
        }
    }

    /// 节流推送：避免高频 readabilityHandler 回调打爆主线程。
    private func flushSnapshotInternal() {
        // 简单策略：每次有新数据就推送完整快照，但由 dispatch async 到主线程自然节流。
        let snapshot = String(data: stdoutBuffer, encoding: .utf8) ?? ""
        guard snapshot.count != lastSnapshotLen else { return }
        lastSnapshotLen = snapshot.count
        DispatchQueue.main.async { [weak self] in
            self?.onOutput?(snapshot)
        }
    }

    /// 强制推送一次完整快照（用于进程退出时确保最后的数据显示）。
    private func flushSnapshot(force: Bool) {
        let snapshot = String(data: stdoutBuffer, encoding: .utf8) ?? ""
        lastSnapshotLen = snapshot.count
        DispatchQueue.main.async { [weak self] in
            self?.onOutput?(snapshot)
        }
    }

    private func markTerminated(exitCode: Int32) {
        guard !hasTerminated else { return }
        hasTerminated = true
        let code = exitCode
        DispatchQueue.main.async { [weak self] in
            self?.onExit?(code)
        }
    }

    // MARK: - Terminal fallback

    /// 在外部 Terminal.app 中运行命令（作为交互式运行的兜底方案）。
    ///
    /// 用 `osascript` 让 Terminal.app 打开新窗口执行给定命令字符串。
    static func openInTerminal(command: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        do {
            try task.run()
            return true
        } catch {
            DMLogger.error("openInTerminal failed: \(error.localizedDescription)", name: "InteractiveProcessRunner")
            return false
        }
    }
}
