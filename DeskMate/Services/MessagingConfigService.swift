import Foundation

/// 消息网关配置服务 — 封装飞书/Lark/微信的配置读写与命令执行。
///
/// 职责：
/// 1. 读写 `~/.hermes/.env` 中的 `FEISHU_*` / `WEIXIN_*` 变量（复用 `HermesConfigWriter`）。
/// 2. 启动交互式 `hermes gateway setup` 进程（用 `InteractiveProcessRunner`）。
/// 3. 安装微信依赖、重装 messaging 扩展（用 `StreamingProcessRunner`）。
/// 4. 启停网关（转发到 `HermesGatewayService`）。
///
/// 配置读写方法是同步的（直接调用 `HermesConfigWriter`），可在任意线程调用；
/// 调用方通常在 `Task.detached` 中调用后用 `await MainActor.run` 切回主线程更新 UI。
/// 命令路径与 `HermesGatewayService` 保持一致：
/// `{hermesHome}/hermes-agent/venv/bin/python -m hermes_cli.main ...`。
final class MessagingConfigService {

    static let shared = MessagingConfigService()

    private init() {}

    // MARK: - Paths

    /// Hermes 主目录（`~/.hermes`）。
    var hermesHome: String { AppConstants.resolveHermesHome() }

    /// Hermes venv 内的 python 可执行文件路径。
    /// 与 `HermesGatewayService.hermesPython(_:)` 一致。
    var pythonPath: String {
        let repoDir = (hermesHome as NSString).appendingPathComponent(AppConstants.hermesAgentDir)
        let venvDir = (repoDir as NSString).appendingPathComponent(AppConstants.hermesVenvDir)
        let binDir = (venvDir as NSString).appendingPathComponent("bin")
        return (binDir as NSString).appendingPathComponent("python")
    }

    /// hermes-agent 仓库目录。
    private var agentRepoDir: String {
        (hermesHome as NSString).appendingPathComponent(AppConstants.hermesAgentDir)
    }

    /// 供 Terminal fallback 使用的 hermesHome 别名。
    var hermesHomeForTerminal: String { hermesHome }

    /// 供 Terminal fallback 使用的 pythonPath 别名。
    var pythonPathForTerminal: String { pythonPath }

    // MARK: - Config read / write

    /// 读取飞书配置（从 `~/.hermes/.env`）。
    func loadFeishuConfig() -> FeishuConfig {
        let env = HermesConfigWriter.shared.readAllEnvVars()
        return FeishuConfig.fromEnvVars(env)
    }

    /// 保存飞书配置到 `~/.hermes/.env`。
    /// 先移除所有 `FEISHU_` 变量，再写入新值，避免残留已删除字段。
    func saveFeishuConfig(_ cfg: FeishuConfig) {
        let writer = HermesConfigWriter.shared
        writer.removeEnvVarsWithPrefix("FEISHU_")
        writer.writeEnvVars(cfg.toEnvVars())
        DMLogger.log("[MessagingConfigService] saved FeishuConfig", name: "MessagingConfigService")
    }

    /// 读取微信配置（从 `~/.hermes/.env`）。
    func loadWeixinConfig() -> WeixinConfig {
        let env = HermesConfigWriter.shared.readAllEnvVars()
        return WeixinConfig.fromEnvVars(env)
    }

    /// 保存微信配置到 `~/.hermes/.env`。
    func saveWeixinConfig(_ cfg: WeixinConfig) {
        let writer = HermesConfigWriter.shared
        writer.removeEnvVarsWithPrefix("WEIXIN_")
        writer.writeEnvVars(cfg.toEnvVars())
        DMLogger.log("[MessagingConfigService] saved WeixinConfig", name: "MessagingConfigService")
    }

    // MARK: - Interactive: hermes gateway setup

    /// 启动交互式 `hermes gateway setup` 进程。
    ///
    /// 使用 `python -u`（unbuffered）+ `PYTHONUNBUFFERED=1` 双保险，确保交互式输出
    /// （平台选择提示、二维码 ASCII）实时推送到 stdout，用户在 App 内能看到。
    ///
    /// - Parameter onOutput: stdout+stderr 合并后的完整快照回调（主线程）。
    /// - Returns: runner 句柄；调用方持有以发送 stdin 或终止。
    func startGatewaySetup(
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) -> InteractiveProcessRunner {
        let runner = InteractiveProcessRunner()
        let env = buildHermesEnv()
        runner.start(
            executable: pythonPath,
            args: ["-u", "-m", "hermes_cli.main", "gateway", "setup"],
            environment: env,
            currentDirectory: hermesHome,
            onOutput: onOutput,
            onExit: onExit
        )
        return runner
    }

    // MARK: - Non-interactive: install deps

    /// 安装微信依赖 `aiohttp` + `cryptography`（用系统 `uv` 安装到 venv）。
    ///
    /// venv 中没有 pip，所以用系统 `uv pip install --python <venv-python>` 来安装。
    func installWeixinDeps(
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) {
        guard let uvPath = findSystemUv() else {
            DispatchQueue.main.async {
                onOutput("错误：未找到 uv 可执行文件。\n请先安装 uv：curl -LsSf https://astral.sh/uv/install.sh | sh\n")
                onExit(-1)
            }
            return
        }
        let py = self.pythonPath
        let env = buildHermesEnv()
        Task.detached(priority: .userInitiated) {
            do {
                let result = try await StreamingProcessRunner.run(
                    executable: uvPath,
                    args: ["pip", "install", "--python", py, "aiohttp", "cryptography"],
                    environment: env,
                    timeout: 300,
                    logName: "MessagingConfigService.deps",
                    onOutput: { output in
                        DispatchQueue.main.async { onOutput(output) }
                    }
                )
                await MainActor.run { onExit(result.exitCode) }
            } catch {
                await MainActor.run { onExit(-1) }
            }
        }
    }

    /// 重装 messaging 扩展：`cd ~/.hermes/hermes-agent && uv pip install -e ".[messaging]"`。
    ///
    /// 用系统 `uv` 安装到 venv，需要 `--python` 指定 venv python。
    /// `StreamingProcessRunner` 不支持 `currentDirectory`，所以用 `/bin/bash -c` 包一层 cd。
    func reinstallMessagingExt(
        onOutput: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) {
        guard let uvPath = findSystemUv() else {
            DispatchQueue.main.async {
                onOutput("错误：未找到 uv 可执行文件。\n请先安装 uv：curl -LsSf https://astral.sh/uv/install.sh | sh\n")
                onExit(-1)
            }
            return
        }
        let repo = self.agentRepoDir
        let py = self.pythonPath
        let cmd = "cd '\(repo)' && '\(uvPath)' pip install --python '\(py)' -e '.[messaging]'"
        let env = buildHermesEnv()

        Task.detached(priority: .userInitiated) {
            do {
                let result = try await StreamingProcessRunner.run(
                    executable: "/bin/bash",
                    args: ["-c", cmd],
                    environment: env,
                    timeout: 600,
                    logName: "MessagingConfigService.messaging-ext",
                    onOutput: { output in
                        DispatchQueue.main.async { onOutput(output) }
                    }
                )
                await MainActor.run { onExit(result.exitCode) }
            } catch {
                await MainActor.run { onExit(-1) }
            }
        }
    }

    // MARK: - Gateway lifecycle (forward to HermesGatewayService)

    /// 启动网关 — 转发到 `HermesGatewayService.shared.startGateway`。
    @discardableResult
    func startGateway() async -> Bool {
        return await HermesGatewayService.shared.startGateway(port: AppConstants.defaultGatewayPort)
    }

    /// 停止网关 — 转发到 `HermesGatewayService.shared.stopGateway`。
    func stopGateway() async {
        await HermesGatewayService.shared.stopGateway(port: AppConstants.defaultGatewayPort)
    }

    /// 健康检查 — 转发到 `HermesGatewayService.shared.isHealthy`。
    func isGatewayHealthy() async -> Bool {
        return await HermesGatewayService.shared.isHealthy(port: AppConstants.defaultGatewayPort)
    }

    // MARK: - Private

    /// 构造子进程环境变量：继承当前环境 + 注入 HERMES_HOME + PYTHONUNBUFFERED。
    ///
    /// `PYTHONUNBUFFERED=1` 是关键 — Python 在管道中默认块缓冲，不加这个的话
    /// `hermes gateway setup` 的交互式输出（平台选择提示、二维码 ASCII）不会实时
    /// 推送到 stdout，用户在 App 内看不到任何输出。
    /// 同时把 `~/.local/bin` 加入 PATH，确保 `uv` 等工具可被找到。
    private func buildHermesEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HERMES_HOME"] = hermesHome
        env["PYTHONUNBUFFERED"] = "1"
        let localBin = (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin")
        if let currentPath = env["PATH"] {
            env["PATH"] = "\(localBin):\(currentPath)"
        } else {
            env["PATH"] = localBin
        }
        return env
    }

    /// 查找系统 `uv` 可执行文件路径。
    ///
    /// venv 中没有 pip 也没有 uv，所以依赖安装需要用系统安装的 uv。
    /// 优先检查常见位置（`~/.local/bin/uv`、`/opt/homebrew/bin/uv`），
    /// 找不到则用 `which uv` 查找。
    private func findSystemUv() -> String? {
        let candidates = [
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/uv"),
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["uv"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = path, !path.isEmpty,
               FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}
        return nil
    }
}
