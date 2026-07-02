import Foundation

/// 流式执行外部命令的共享工具。
///
/// 复用 `OpenVikingProvider` 中经过验证的 Process 流式模式：
/// - 用 `readDataToEndOfFile()` 在后台队列排空管道（避免 `readabilityHandler` 大输出丢数据/死锁）；
/// - `terminationHandler` + `ResumeOnceFlag` 唤醒 async continuation；
/// - `OutputTicker` 每 0.4s 节流推送尾部日志；
/// - 超时强杀（SIGTERM → 2s 后 SIGKILL）。
///
/// 相比 `OpenVikingProvider.runProcess`，本工具额外支持注入自定义 `environment`
/// （用于进程级 git insteadOf 镜像）和 `onProcessReady` 回调（供外部 `terminate()` 取消）。
///
/// `StreamCapture` / `ResumeOnceFlag` / `OutputTicker` 直接复用
/// `OpenVikingProvider.swift` 末尾的 internal 声明，不在此重复定义。
enum StreamingProcessRunner {

    /// 命令执行结果。
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// 同步执行一次性外部命令，支持超时、自定义环境、实时输出回调和进程句柄回调。
    ///
    /// - Parameters:
    ///   - environment: `nil` 时继承 `ProcessInfo.processInfo.environment`；
    ///     传入则完全替换子进程环境（用于注入进程级 git 配置）。
    ///   - onOutput: 每 0.4s 推送一次 stdout+stderr 合并后的尾部若干非空行。
    ///   - onProcessReady: `process.run()` 成功后立即回调，外部可保存 `Process` 引用以便取消。
    nonisolated static func run(
        executable: String,
        args: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval,
        logName: String = "StreamingProcessRunner",
        onOutput: ((String) -> Void)? = nil,
        onProcessReady: ((Process) -> Void)? = nil
    ) async throws -> Result {
        let argv = ([executable] + args).joined(separator: " ")
        DMLogger.log("run: starting argv=\(argv)", name: logName)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.environment = environment ?? ProcessInfo.processInfo.environment

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

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

            // 并发排空 stdout 与 stderr（两条独立队列）。
            // 若顺序读取，当 stderr 填满 64KB 管道缓冲而 stdout 仍阻塞在
            // readDataToEndOfFile 时会死锁；install.sh 输出量大，必须并发。
            // readDataToEndOfFile() 在进程关闭管道（EOF，即退出）时返回。
            let readGroup = DispatchGroup()
            let stdoutQueue = DispatchQueue(label: "streamingrunner.stdout", qos: .userInitiated)
            let stderrQueue = DispatchQueue(label: "streamingrunner.stderr", qos: .userInitiated)

            readGroup.enter()
            stdoutQueue.async {
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                if !outData.isEmpty { stdoutCapture.append(outData) }
                readGroup.leave()
            }
            readGroup.enter()
            stderrQueue.async {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !errData.isEmpty { stderrCapture.append(errData) }
                readGroup.leave()
            }
            // 两条管道都读完（EOF）后停止节流推送
            readGroup.notify(queue: .global()) {
                outputTicker.stop()
            }

            process.terminationHandler = { proc in
                DMLogger.log(
                    "run: terminationHandler fired exit=\(proc.terminationStatus)",
                    name: logName
                )
                outputTicker.stop()
                // 等两条管道都排空后再 resume（readGroup 在 EOF 时 leave 完成）
                readGroup.notify(queue: .global()) {
                    if resumedFlag.tryResume() {
                        let finalOut = stdoutCapture.snapshot()
                        let finalErr = stderrCapture.snapshot()
                        let tail = Self.lastNonEmptyLines(in: finalOut + finalErr, max: 6)
                        onOutput?(tail)
                        DMLogger.log(
                            "run: returning exit=\(proc.terminationStatus) " +
                            "out=\(finalOut.count)B err=\(finalErr.count)B",
                            name: logName
                        )
                        continuation.resume(returning: Result(
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
                    "run: process started pid=\(process.processIdentifier) argv=\(argv)",
                    name: logName
                )
                onProcessReady?(process)
            } catch {
                DMLogger.error("run: process.run() threw: \(error)", name: logName)
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
                    let tail = Self.lastNonEmptyLines(
                        in: stdoutCapture.snapshot() + stderrCapture.snapshot(),
                        max: 3
                    )
                    DMLogger.log(
                        "run: heartbeat t=\(elapsed)s pid=\(process.processIdentifier) " +
                        "running=\(process.isRunning) tail=\(tail)",
                        name: logName
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
                        "run: timeout (>\(Int(timeout))s) — terminating. argv=\(argv)",
                        name: logName
                    )
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            DMLogger.error(
                                "run: SIGKILL pid=\(process.processIdentifier)",
                                name: logName
                            )
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        }
    }

    /// 剥离 ANSI 颜色/样式转义码（如 `\033[0;36m`），便于关键字匹配。
    nonisolated static func stripANSI(_ s: String) -> String {
        // 匹配 ESC [ 参数... 字母  形式的 CSI 序列；也兼容 OSC 等以 BEL 结尾的序列。
        var result = ""
        result.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{001B}" {
                // 跳过 ESC 及其后的序列
                var j = s.index(after: i)
                if j < s.endIndex {
                    if s[j] == "[" {
                        // CSI: ESC [ params(0x30-0x3F) mid(0x20-0x2F) final(0x40-0x7E)
                        j = s.index(after: j)
                        while j < s.endIndex {
                            let c = s[j]
                            if c.asciiValue.map({ (0x40...0x7E).contains($0) }) == true {
                                j = s.index(after: j)
                                break
                            } else {
                                j = s.index(after: j)
                            }
                        }
                    } else if s[j] == "]" {
                        // OSC: ESC ] ... BEL(0x07) 或 ST(ESC \)
                        j = s.index(after: j)
                        while j < s.endIndex {
                            if s[j] == "\u{07}" {
                                j = s.index(after: j)
                                break
                            }
                            if s[j] == "\u{001B}",
                               s.index(after: j) < s.endIndex,
                               s[s.index(after: j)] == "\\" {
                                j = s.index(j, offsetBy: 2)
                                break
                            }
                            j = s.index(after: j)
                        }
                    } else {
                        // 其他 ESC + 单字符序列（如 ESC = ）
                        j = s.index(after: j)
                    }
                }
                i = j
            } else {
                result.append(s[i])
                i = s.index(after: i)
            }
        }
        return result
    }

    /// 取出字符串末尾若干非空行（用于 UI 实时进度展示）。
    nonisolated static func lastNonEmptyLines(in s: String, max: Int) -> String {
        let lines = s.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return "" }
        let tail = lines.suffix(max)
        return tail.joined(separator: "\n")
    }
}
