import SwiftUI
import AppKit
import Combine

/// Hermes 后端管理（更新 / 卸载 / 清除数据）。
///
/// 设置页通过该 ViewModel 执行 Hermes 的维护操作，并在弹窗中展示实时日志。
/// 所有耗时操作均在后台执行，UI 状态通过 @Published 同步到主线程。
@MainActor
final class HermesManagementViewModel: ObservableObject {

    // MARK: - UI State

    @Published var hermesVersion: String?
    @Published var isHermesInstalled: Bool = false

    /// 是否正在检测 Hermes 安装状态。
    @Published var isLoadingStatus: Bool = true

    /// 当前是否有操作正在进行。
    @Published var isRunning: Bool = false

    /// 当前操作类型（用于弹窗标题）。
    @Published var currentOperation: Operation?

    /// 实时日志文本。
    @Published var logText: String = ""

    /// 是否显示日志弹窗。
    @Published var showLogSheet: Bool = false

    /// 是否显示镜像选择 Alert。
    @Published var showMirrorAlert: Bool = false

    /// 确认对话框类型。
    @Published var confirmAlert: ConfirmAlert?

    /// 操作结果提示。
    @Published var resultAlert: ResultAlert?

    // MARK: - Internal State

    private var currentRunner: InteractiveProcessRunner?
    private var timeoutWorkItem: DispatchWorkItem?

    /// 待执行的更新操作（用户在镜像 Alert 中做出选择后使用）。
    private var pendingUpdateMirror: Bool = false

    // MARK: - Types

    enum Operation: String {
        case update = "更新 Hermes"
        case uninstall = "卸载 Hermes"
        case clearData = "清除全部数据"
    }

    enum ConfirmAlert: Identifiable {
        case uninstall
        case clearData

        var id: String {
            switch self {
            case .uninstall: return "uninstall"
            case .clearData: return "clearData"
            }
        }

        var title: String {
            switch self {
            case .uninstall: return "确认卸载 Hermes"
            case .clearData: return "确认清除全部数据"
            }
        }

        var message: String {
            switch self {
            case .uninstall:
                return "卸载将移除 Hermes 程序文件（保留 ~/.hermes 下的配置与数据）。卸载完成后 DeskMate 将自动重启。"
            case .clearData:
                return "清除全部数据将删除 ~/.hermes 目录下的所有配置、记忆、会话与缓存。此操作不可恢复，DeskMate 将自动重启并重新进入引导。"
            }
        }

        var confirmButton: String {
            switch self {
            case .uninstall: return "卸载"
            case .clearData: return "清除"
            }
        }
    }

    struct ResultAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let shouldRestart: Bool
    }

    // MARK: - Lifecycle

    init() {
        refreshHermesStatus()
    }

    // MARK: - Public Actions

    /// 刷新 Hermes 安装状态与版本号。
    func refreshHermesStatus() {
        isLoadingStatus = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status = Self.checkHermesStatus()
            DispatchQueue.main.async { [weak self] in
                self?.isHermesInstalled = status.installed
                self?.hermesVersion = status.version
                self?.isLoadingStatus = false
            }
        }
    }

    /// 用户点击“更新 Hermes”——先弹出镜像选择 Alert。
    func startUpdate() {
        guard !isRunning else { return }
        guard isHermesInstalled else {
            resultAlert = ResultAlert(
                title: "无法更新",
                message: "未检测到 Hermes 安装，请先完成引导安装。",
                shouldRestart: false
            )
            return
        }
        showMirrorAlert = true
    }

    /// 用户在镜像 Alert 中做出选择后开始更新。
    func confirmUpdate(useMirror: Bool) {
        showMirrorAlert = false
        pendingUpdateMirror = useMirror
        startOperation(.update)
    }

    /// 用户点击“卸载 Hermes”。
    func requestUninstall() {
        guard !isRunning else { return }
        confirmAlert = .uninstall
    }

    /// 用户点击“清除全部数据”。
    func requestClearData() {
        guard !isRunning else { return }
        confirmAlert = .clearData
    }

    /// 确认后执行卸载。
    func performUninstall() {
        confirmAlert = nil
        startOperation(.uninstall)
    }

    /// 确认后执行清除数据。
    func performClearData() {
        confirmAlert = nil
        startOperation(.clearData)
    }

    /// 取消当前正在进行的操作。
    func cancelOperation() {
        currentRunner?.terminate()
        currentRunner = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        isRunning = false
        appendLog("\n操作已取消。")
    }

    /// 关闭日志弹窗（不取消后台进程）。
    func dismissLogSheet() {
        showLogSheet = false
    }

    /// 操作成功后重启 DeskMate。
    func restartApp() {
        Self.relaunchApplication()
    }

    // MARK: - Operation Orchestration

    private func startOperation(_ operation: Operation) {
        currentOperation = operation
        logText = ""
        isRunning = true
        showLogSheet = true

        Task { [weak self] in
            guard let self = self else { return }

            // 1. 先停止 gateway，避免文件占用或配置不一致。
            await self.stopGateway()

            switch operation {
            case .update:
                await self.runUpdate()
            case .uninstall:
                await self.runUninstall()
            case .clearData:
                await self.runClearData()
            }
        }
    }

    private func stopGateway() async {
        appendLog("正在停止 Hermes Gateway...")

        let hermesHome = AppConstants.resolveHermesHome()
        let env = Self.baseEnvironment(hermesHome: hermesHome)

        // 优先使用 hermes gateway stop --all 停止所有网关（包括非本进程启动的）。
        if let hermesBin = Self.findHermesBinary(hermesHome: hermesHome) {
            let command = "\"\(hermesBin)\" gateway stop --all"
            let output = Self.runShellSync(command, environment: env)
            appendLog(output.isEmpty ? "已执行 hermes gateway stop --all" : output)
        }

        // 兜底：停止本应用注册过的 Gateway 进程。
        await HermesGatewayService.shared.stopAllGateways()
        appendLog("Gateway 已停止。\n")
    }

    // MARK: - Update

    private func runUpdate() async {
        appendLog("开始更新 Hermes...")

        let hermesHome = AppConstants.resolveHermesHome()
        guard let hermesBin = Self.findHermesBinary(hermesHome: hermesHome) else {
            finishOperation(success: false, message: "未找到 hermes 可执行文件。")
            return
        }

        let useMirror = pendingUpdateMirror
        var env = Self.baseEnvironment(hermesHome: hermesHome)
        if useMirror {
            env = Self.applyMirrorEnvironment(env)
            appendLog("已启用国内镜像加速。\n")
        }

        let command = "\"\(hermesBin)\" update"
        await runShellCommand(
            command,
            environment: env,
            timeout: 30 * 60,
            operation: .update
        ) { [weak self] success in
            if success {
                self?.finishOperation(
                    success: true,
                    message: "Hermes 更新完成，DeskMate 即将重启。",
                    shouldRestart: true
                )
            } else {
                self?.finishOperation(
                    success: false,
                    message: "Hermes 更新失败，请查看日志排查问题。"
                )
            }
        }
    }

    // MARK: - Uninstall

    private func runUninstall() async {
        appendLog("开始卸载 Hermes...")

        let hermesHome = AppConstants.resolveHermesHome()

        // 优先尝试官方 hermes uninstall 命令；失败后回退到手动删除。
        if let hermesBin = Self.findHermesBinary(hermesHome: hermesHome) {
            appendLog("执行 hermes uninstall...\n")
            let command = "\"\(hermesBin)\" uninstall"
            await runShellCommand(
                command,
                environment: Self.baseEnvironment(hermesHome: hermesHome),
                timeout: 5 * 60,
                operation: .uninstall
            ) { [weak self] success in
                // 无论 uninstall 命令是否成功，都兜底清理已知入口与仓库目录。
                self?.performManualUninstallCleanup(hermesHome: hermesHome)
                if success {
                    self?.finishOperation(
                        success: true,
                        message: "Hermes 已卸载，DeskMate 即将重启。",
                        shouldRestart: true
                    )
                } else {
                    self?.finishOperation(
                        success: false,
                        message: "Hermes 卸载命令返回错误，已尝试兜底清理，请检查日志。",
                        shouldRestart: true
                    )
                }
            }
        } else {
            performManualUninstallCleanup(hermesHome: hermesHome)
            finishOperation(
                success: true,
                message: "Hermes 程序文件已移除，DeskMate 即将重启。",
                shouldRestart: true
            )
        }
    }

    private func performManualUninstallCleanup(hermesHome: String) {
        let localBinHermes = (Self.realHomeDirectory() as NSString)
            .appendingPathComponent(".local/bin/hermes")
        let agentDir = (hermesHome as NSString).appendingPathComponent(AppConstants.hermesAgentDir)

        let cleanup = """
        rm -f '\(localBinHermes)' && rm -rf '\(agentDir)'
        """
        let result = Self.runShellSync(cleanup)
        appendLog("\n兜底清理结果:\n\(result.isEmpty ? "完成" : result)")
    }

    // MARK: - Clear Data

    private func runClearData() async {
        appendLog("开始清除全部数据...")

        let hermesHome = AppConstants.resolveHermesHome()
        let localBinHermes = (Self.realHomeDirectory() as NSString)
            .appendingPathComponent(".local/bin/hermes")
        let agentDir = (hermesHome as NSString).appendingPathComponent(AppConstants.hermesAgentDir)

        let command = "rm -f '\(localBinHermes)' && rm -rf '\(agentDir)' && rm -rf '\(hermesHome)'"
        await runShellCommand(
            command,
            environment: Self.baseEnvironment(hermesHome: hermesHome),
            timeout: 5 * 60,
            operation: .clearData
        ) { [weak self] success in
            // 清除后重置 onboarding 标记，让下次启动重新进入引导。
            UserDefaults.standard.set(false, forKey: "onboarding_completed")
            if success {
                self?.finishOperation(
                    success: true,
                    message: "全部数据已清除，DeskMate 即将重启并重新进入引导。",
                    shouldRestart: true
                )
            } else {
                self?.finishOperation(
                    success: false,
                    message: "清除数据失败，请检查权限或日志。"
                )
            }
        }
    }

    // MARK: - Shell Execution

    /// 通过 /bin/bash -c 执行命令，并实时流式输出到日志弹窗。
    private func runShellCommand(
        _ command: String,
        environment: [String: String],
        timeout: TimeInterval,
        operation: Operation,
        completion: @escaping @MainActor (Bool) -> Void
    ) async {
        let prefix = logText
        currentRunner = InteractiveProcessRunner()

        // 超时强杀
        let timeoutItem = DispatchWorkItem { [weak self] in
            self?.appendLog("\n操作超时（\(Int(timeout))秒），正在终止...")
            self?.currentRunner?.terminate()
        }
        timeoutWorkItem = timeoutItem
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        let success = currentRunner?.start(
            executable: "/bin/bash",
            args: ["-c", command],
            environment: environment,
            currentDirectory: AppConstants.resolveHermesHome(),
            onOutput: { [weak self] snapshot in
                self?.logText = prefix + snapshot
            },
            onExit: { [weak self] code in
                self?.timeoutWorkItem?.cancel()
                self?.timeoutWorkItem = nil
                self?.currentRunner = nil
                Task { @MainActor in
                    let success = code == 0
                    self?.isRunning = false
                    completion(success)
                }
            }
        ) ?? false

        if !success {
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            currentRunner = nil
            isRunning = false
            completion(false)
        }
    }

    // MARK: - Completion

    private func finishOperation(success: Bool, message: String, shouldRestart: Bool = false) {
        isRunning = false
        let title = success ? "操作完成" : "操作失败"
        appendLog("\n\(title): \(message)")
        resultAlert = ResultAlert(
            title: title,
            message: message,
            shouldRestart: shouldRestart
        )
        refreshHermesStatus()
    }

    private func appendLog(_ text: String) {
        logText.append(text + "\n")
    }

    // MARK: - Static Helpers

    /// 检测 Hermes 是否已安装并返回版本号。
    private static func checkHermesStatus() -> (installed: Bool, version: String?) {
        let hermesHome = AppConstants.resolveHermesHome()

        if let hermesBin = findHermesBinary(hermesHome: hermesHome) {
            let version = runShellSync("\"\(hermesBin)\" --version 2>/dev/null")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (true, version.isEmpty ? nil : version)
        }

        // 兜底：检查仓库目录是否存在
        let agentDir = (hermesHome as NSString).appendingPathComponent(AppConstants.hermesAgentDir)
        let fm = FileManager.default
        let installed = fm.fileExists(atPath: agentDir)
        return (installed, nil)
    }

    /// 查找 hermes 可执行文件路径。
    private static func findHermesBinary(hermesHome: String) -> String? {
        let fm = FileManager.default
        let candidates = [
            (hermesHome as NSString).appendingPathComponent("hermes-agent/venv/bin/hermes"),
            (realHomeDirectory() as NSString).appendingPathComponent(".local/bin/hermes"),
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        let which = runShellSync("which hermes 2>/dev/null")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !which.isEmpty && fm.isExecutableFile(atPath: which) {
            return which
        }
        return nil
    }

    /// 基础子进程环境变量。
    private static func baseEnvironment(hermesHome: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HERMES_HOME"] = hermesHome
        env["PYTHONUNBUFFERED"] = "1"
        env["PATH"] = expandedPath()
        return env
    }

    /// 注入国内镜像环境变量（与 OnboardingViewModel 安装逻辑保持一致）。
    private static func applyMirrorEnvironment(_ env: [String: String]) -> [String: String] {
        var env = env
        env["GIT_CONFIG_COUNT"] = "1"
        env["GIT_CONFIG_KEY_0"] = "url.\(kDefaultGithubMirror).insteadOf"
        env["GIT_CONFIG_VALUE_0"] = "https://github.com/"
        env["PIP_INDEX_URL"] = kDefaultPipIndexUrl
        env["UV_INDEX_URL"] = kDefaultPipIndexUrl
        env["PIP_TRUSTED_HOST"] = "pypi.tuna.tsinghua.edu.cn"
        return env
    }

    /// 扩展 PATH，确保子进程能找到 uv / node 等工具。
    private static func expandedPath() -> String {
        var path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let home = NSHomeDirectory()
        for entry in ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"].reversed() {
            if !path.contains(entry) {
                path = "\(entry):\(path)"
            }
        }
        let nvmNodeBin = runShellSync("ls -d \(home)/.nvm/versions/node/*/bin 2>/dev/null | tail -1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !nvmNodeBin.isEmpty && !path.contains(nvmNodeBin) {
            path = "\(nvmNodeBin):\(path)"
        }
        return path
    }

    private static func runShellSync(_ command: String, environment: [String: String]? = nil) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        if let environment = environment {
            task.environment = environment
        }
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 获取真实用户 Home 目录（沙盒环境下 NSHomeDirectory 返回容器路径）。
    private static func realHomeDirectory() -> String {
        let pw = getpwuid(getuid())
        if let dir = pw?.pointee.pw_dir {
            return String(cString: dir)
        }
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            return home
        }
        let containerHome = NSHomeDirectory()
        let components = containerHome.split(separator: "/")
        if components.count >= 3 {
            return "/" + components[1] + "/" + components[2]
        }
        return containerHome
    }

    /// 重启 DeskMate 应用。
    ///
    /// 使用单实例安全的方式：等待当前进程退出后再 `open`（不带 `-n`），避免多开。
    private static func relaunchApplication() {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        /bin/bash -c "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; sleep 0.5; open '\(bundlePath)'"
        """
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]
        try? task.run()

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
