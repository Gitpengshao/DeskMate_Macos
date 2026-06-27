import Foundation

/// 可选技能安装/卸载服务 — 封装 `hermes skills install/uninstall` CLI 调用。
///
/// 实际行为：
/// - Install: 在 hermes venv 下执行 `hermes skills install official/<category>/<skill> --yes`
/// - Uninstall: 在 hermes venv 下执行 `hermes skills uninstall <skill>`
///
/// 与 Flutter 端 `hermes skills` CLI 完全对齐（参见 `~/.hermes/hermes-agent/hermes_cli`）。
nonisolated final class SkillInstallService {

    /// 单例 — UI 多次调用共享同一份状态。
    static let shared = SkillInstallService()

    /// 默认安装/卸载超时（秒）。install 可能较慢（下载脚本/依赖），留 10 分钟。
    private let defaultTimeout: TimeInterval = 10 * 60

    /// 最近一次失败的原始 stderr（供 UI 展示）。
    private(set) var lastError: String?

    private init() {}

    // MARK: - Public

    /// 安装一个可选技能。
    ///
    /// - Parameters:
    ///   - category: 分类目录名（例如 "blockchain"）。
    ///   - skillId: 技能 id（例如 "solana"）。
    /// - Returns: 是否安装成功（退出码 0）。
    @discardableResult
    func install(category: String, skillId: String) async -> Bool {
        let identifier = "official/\(category)/\(skillId)"
        DMLogger.log(
            "installSkill: identifier=\(identifier)",
            name: "SkillInstallService"
        )
        let result = await runHermesSkills(
            args: ["install", identifier, "--yes"],
            timeout: defaultTimeout
        )
        if !result.success {
            DMLogger.error(
                "installSkill: failed (\(result.exitCode)) \(result.stderr)",
                name: "SkillInstallService"
            )
            lastError = result.stderr.isEmpty ? result.stdout : result.stderr
        } else {
            DMLogger.log(
                "installSkill: ok \(identifier)",
                name: "SkillInstallService"
            )
            lastError = nil
        }
        return result.success
    }

    /// 卸载一个技能。
    ///
    /// - Parameter skillId: 技能 id。
    /// - Returns: 是否卸载成功。
    @discardableResult
    func uninstall(skillId: String) async -> Bool {
        DMLogger.log(
            "uninstallSkill: id=\(skillId)",
            name: "SkillInstallService"
        )
        let result = await runHermesSkills(
            args: ["uninstall", skillId],
            timeout: 60
        )
        if !result.success {
            DMLogger.error(
                "uninstallSkill: failed (\(result.exitCode)) \(result.stderr)",
                name: "SkillInstallService"
            )
            lastError = result.stderr.isEmpty ? result.stdout : result.stderr
        } else {
            DMLogger.log(
                "uninstallSkill: ok \(skillId)",
                name: "SkillInstallService"
            )
            lastError = nil
        }
        return result.success
    }

    // MARK: - Process

    /// 在 hermes venv 下执行 `hermes skills <args>` 子进程。
    private func runHermesSkills(args: [String], timeout: TimeInterval) async -> ShellResult {
        let hermesHome = AppConstants.resolveHermesHome()
        let hermesBin = (hermesHome as NSString)
            .appendingPathComponent("hermes-agent/venv/bin/hermes")
        let fm = FileManager.default
        if !fm.isExecutableFile(atPath: hermesBin) {
            // 兜底: 尝试调用 ~/.local/bin/hermes
            let fallback = "/Users/mac002/.local/bin/hermes"
            if fm.isExecutableFile(atPath: fallback) {
                return await runProcess(
                    executable: fallback,
                    args: ["skills"] + args,
                    timeout: timeout
                )
            }
            return ShellResult(
                success: false,
                exitCode: -1,
                stdout: "",
                stderr: "hermes CLI 未找到: \(hermesBin)"
            )
        }
        return await runProcess(
            executable: hermesBin,
            args: ["skills"] + args,
            timeout: timeout
        )
    }

    /// 通用子进程执行（异步 + 超时）。
    private func runProcess(
        executable: String,
        args: [String],
        timeout: TimeInterval
    ) async -> ShellResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ShellResult, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            // 继承当前环境变量（HERMES_HOME 等）
            process.environment = ProcessInfo.processInfo.environment

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let lock = NSLock()
            var didResume = false

            func resume(_ result: ShellResult) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                cont.resume(returning: result)
            }

            process.terminationHandler = { proc in
                let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let ok = proc.terminationStatus == 0
                resume(ShellResult(
                    success: ok,
                    exitCode: proc.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                ))
            }

            do {
                try process.run()
            } catch {
                resume(ShellResult(
                    success: false,
                    exitCode: -1,
                    stdout: "",
                    stderr: "process.run failed: \(error.localizedDescription)"
                ))
                return
            }

            // 超时强制终止
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    DMLogger.error(
                        "runProcess: timeout (\(timeout)s), killing pid=\(process.processIdentifier)",
                        name: "SkillInstallService"
                    )
                    kill(process.processIdentifier, SIGTERM)
                    // 再给 2s，否则 SIGKILL
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Result

/// 子进程执行结果。
struct ShellResult {
    let success: Bool
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
