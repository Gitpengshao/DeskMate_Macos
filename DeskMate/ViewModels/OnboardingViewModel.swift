import Foundation
import Combine
import AppKit

/// 管理 onboarding 向导状态 — 步骤导航、真实环境检测、Hermes 安装和 AI 大模型配置。
///
/// 对齐 Flutter 的 OnboardingViewModel (Riverpod Notifier)。
class OnboardingViewModel: ObservableObject {

    @Published var model: OnboardingModel

    /// 环境检测完成后发现 Hermes 已安装且大模型已配置（config.yaml 中有 API Key），
    /// 则直接跳过所有 onboarding 步骤进入主页面。
    @Published var didCompleteEarly: Bool = false

    // MARK: - Timers (对齐 Flutter 的 _downloadTimer / _slowDownloadTimer)

    private var downloadTimer: Timer?
    private var slowDownloadTimer: Timer?
    private var installStartTime: Date = Date()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Install Process State（流式安装子进程句柄 + 取消标志 + 单调进度）

    private var installProcess: Process?
    private let installProcessLock = NSLock()
    private var isInstallCancelled: Bool = false
    private let isInstallCancelledLock = NSLock()
    /// 单调递增的 milestone 进度，仅当关键字命中更高档位时才前进。
    private var installMilestone: Double = 0.0
    /// 当前 milestone 达到的时间，用于在 milestone 之间做平滑进度动画。
    private var lastMilestoneTime: Date = Date()
    /// 当前 milestone 的数值，用于平滑进度的基准。
    private var lastMilestoneValue: Double = 0.0
    /// 安装进度档位，用于平滑增长的上限约束。
    private static let progressMilestones: [Double] = [0.0, 0.05, 0.10, 0.15, 0.35, 0.55, 0.75, 0.90, 0.95, 1.0]

    private func setInstallProcess(_ p: Process?) {
        installProcessLock.lock(); installProcess = p; installProcessLock.unlock()
    }
    private func getInstallProcess() -> Process? {
        installProcessLock.lock(); defer { installProcessLock.unlock() }
        return installProcess
    }
    private func setCancelled(_ v: Bool) {
        isInstallCancelledLock.lock(); isInstallCancelled = v; isInstallCancelledLock.unlock()
    }
    private func getCancelled() -> Bool {
        isInstallCancelledLock.lock(); defer { isInstallCancelledLock.unlock() }
        return isInstallCancelled
    }

    // MARK: - Init

    init() {
        // 构建初始 model，对齐 Flutter 的 build()
        let providers = kProviderDisplayNames.map { (key, value) in
            BuiltInModelProvider(
                id: key,
                name: value,
                iconEmoji: kProviderIconEmojis[key] ?? ""
            )
        }

        self.model = OnboardingModel(
            steps: [
                OnboardingStep(index: 0, label: ""),
                OnboardingStep(index: 1, label: ""),
                OnboardingStep(index: 2, label: ""),
            ],
            aiModelOptions: [
                AiModelOption(id: "auto", name: ""),
                AiModelOption(id: "custom", name: "")
            ],
            builtInProviders: providers
        )
    }

    // MARK: - Step Navigation

    /// 前进到下一步或标记为已完成。
    func nextStep() {
        DMLogger.log("nextStep called: currentStep=\(model.currentStep), totalSteps=\(model.totalSteps)", name: "OnboardingViewModel")
        if model.currentStep < model.totalSteps - 1 {
            model.currentStep += 1
            DMLogger.log("nextStep: 已前进到第 \(model.currentStep) 步", name: "OnboardingViewModel")
        } else {
            model.isCompleted = true
            DMLogger.log("nextStep: 已标记为完成", name: "OnboardingViewModel")
        }
    }

    /// 回退到上一步。
    func previousStep() {
        DMLogger.log("previousStep called: currentStep=\(model.currentStep)", name: "OnboardingViewModel")
        if model.currentStep > 0 {
            model.currentStep -= 1
        }
    }

    /// 跳转到指定步骤。
    func goToStep(_ index: Int) {
        DMLogger.log("goToStep called: index=\(index)", name: "OnboardingViewModel")
        guard index >= 0, index < model.totalSteps else { return }
        model.currentStep = index
    }

    // MARK: - Step 1: Environment Check

    /// 运行真实的环境检测（对齐 Flutter 的 startEnvironmentCheck）。
    func startEnvironmentCheck() {
        DMLogger.log("startEnvironmentCheck called", name: "OnboardingViewModel")

        // DispatchQueue.main.async 延迟状态变更，规避按钮事件中触发 @Published
        // 导致的 "layoutSubtreeIfNeeded on a view which is already being laid out" 问题
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 标记为检测中
            self.model.isCheckingEnvironment = true
            DMLogger.log("已设置 isCheckingEnvironment=true", name: "OnboardingViewModel")

            // 展示每个检查项的检测中状态
            let checkIds = ["sys_ver", "network", "python", "hermes", "disk", "gpu"]
            self.model.environmentCheckItems = checkIds.map {
                EnvironmentCheckItem(id: $0, isChecking: true)
            }
        }

        // 异步运行检测
        runEnvironmentChecks { [weak self] results, hermesStatus in
            guard let self = self else { return }

            let items: [EnvironmentCheckItem] = results.map { result in
                let statusText: String
                if result.passed {
                    switch result.id {
                    case "hermes":
                        statusText = "✓ 已安装 \(result.detail ?? "")"
                    case "disk":
                        statusText = "✓ 充足"
                    case "gpu":
                        statusText = result.detail != nil ? "✓ \(result.detail!)" : "✓ 硬件加速可用"
                    default:
                        statusText = "✓ 通过"
                    }
                } else {
                    statusText = result.error ?? "✗ 未通过"
                }
                return EnvironmentCheckItem(
                    id: result.id,
                    isPassed: result.passed,
                    isChecking: false,
                    detail: result.detail,
                    statusText: statusText
                )
            }

            let allPassed = results.allSatisfy { $0.passed }
            let failedIds = results.filter { !$0.passed }.map { $0.id }
            DMLogger.log("所有检测通过: \(allPassed), 失败项: \(failedIds)", name: "OnboardingViewModel")

            self.model.isCheckingEnvironment = false
            self.model.isEnvironmentReady = allPassed
            self.model.environmentCheckItems = items
            self.model.environmentCheckSummary = allPassed
                ? "所有检测通过，可以继续安装"
                : "部分检测未通过，下一步将帮您安装缺失环境"
            self.model.hermesHome = hermesStatus.hermesHome
            self.model.hermesInstalled = hermesStatus.installed
            self.model.hermesConfigured = hermesStatus.configured
            self.model.hermesHasApiKey = hermesStatus.hasApiKey
            self.model.hermesHasModelConfigured = hermesStatus.hasModelConfigured
            self.model.failedCheckIds = failedIds

            // 环境检测完成后刷新当前 SOUL.md 内容，便于第三步展示。
            self.loadSoulFile()

            DMLogger.log("startEnvironmentCheck 完成: isEnvironmentReady=\(self.model.isEnvironmentReady), canAdvance=\(self.model.canAdvance)", name: "OnboardingViewModel")

            let pythonPassed = results.first(where: { $0.id == "python" })?.passed ?? false
            let hermesPassed = results.first(where: { $0.id == "hermes" })?.passed ?? false

            // 对齐 Flutter 的逻辑：installed && configured && hasApiKey
            // Flutter 的 isReady = installed && configured && hasApiKey
            let isFullyConfigured = hermesPassed && hermesStatus.configured && hermesStatus.hasApiKey
            DMLogger.log("判断是否完全配置: hermesPassed=\(hermesPassed), configured=\(hermesStatus.configured), hasApiKey=\(hermesStatus.hasApiKey), isFullyConfigured=\(isFullyConfigured)", name: "OnboardingViewModel")

            if isFullyConfigured {
                DMLogger.log("Hermes 已安装、已配置、API Key 已配置，跳过所有步骤，直接进入主页面", name: "OnboardingViewModel")
                self.completeOnboarding()
                // 延迟触发 early complete，让 UI 有时间渲染
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.didCompleteEarly = true
                }
            } else if pythonPassed && hermesPassed {
                // 如果 Python 和 Hermes 都已安装但配置或 API Key 未配置，跳过第二步安装，直接进入第三步配置
                DMLogger.log("Python 和 Hermes 均已安装，但配置或 API Key 未配置，跳过第二步，直接进入第三步配置", name: "OnboardingViewModel")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.goToStep(2)
                }
            }
        }
    }

    /// 在 macOS 上运行真实的环境检测。
    private func runEnvironmentChecks(
        completion: @escaping ([CheckResult], HermesInstallStatus) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            DMLogger.log("开始运行 6 项环境检测...", name: "OnboardingViewModel")
            var results: [CheckResult] = []

            // sys_ver — macOS 系统版本
            DMLogger.log("[EnvCheck] 开始检测系统版本...", name: "OnboardingViewModel")
            let osVersion = ProcessInfo.processInfo.operatingSystemVersion
            let sysVerDetail = "macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
            results.append(CheckResult(id: "sys_ver", passed: true, detail: sysVerDetail))
            DMLogger.log("[EnvCheck] 系统版本检测完成: \(sysVerDetail)", name: "OnboardingViewModel")

            // network — 网络连通性
            DMLogger.log("[EnvCheck] 开始检测网络连通性...", name: "OnboardingViewModel")
            let networkPassed = self.checkNetworkConnectivity()
            results.append(CheckResult(
                id: "network",
                passed: networkPassed,
                detail: networkPassed ? "已连接" : "未连接",
                error: networkPassed ? nil : "网络不可用"
            ))
            DMLogger.log("[EnvCheck] 网络连通性检测完成: \(networkPassed ? "已连接" : "未连接")", name: "OnboardingViewModel")

            // python — 检查 python3 是否可用
            DMLogger.log("[EnvCheck] 开始检测 Python 环境...", name: "OnboardingViewModel")
            let resolvedHome = self.resolveHermesHome()
            let pythonInfo = self.checkPython(hermesHome: resolvedHome)
            results.append(CheckResult(
                id: "python",
                passed: pythonInfo.available,
                detail: pythonInfo.version,
                error: pythonInfo.available ? nil : "未安装 Python 3"
            ))
            DMLogger.log("[EnvCheck] Python 环境检测完成: available=\(pythonInfo.available), version=\(pythonInfo.version ?? "nil")", name: "OnboardingViewModel")

            // hermes — 检查 Hermes 引擎
            DMLogger.log("[EnvCheck] 开始检测 Hermes 引擎...", name: "OnboardingViewModel")
            let hermesInfo = self.checkHermes(hermesHome: resolvedHome)
            results.append(CheckResult(
                id: "hermes",
                passed: hermesInfo.installed,
                detail: hermesInfo.version,
                error: hermesInfo.installed ? nil : "未安装 Hermes 引擎"
            ))
            DMLogger.log("[EnvCheck] Hermes 引擎检测完成: installed=\(hermesInfo.installed), version=\(hermesInfo.version ?? "nil")", name: "OnboardingViewModel")

            // disk — 检查磁盘可用空间（至少 2GB）
            DMLogger.log("[EnvCheck] 开始检测磁盘空间...", name: "OnboardingViewModel")
            let diskInfo = self.checkDiskSpace()
            results.append(CheckResult(
                id: "disk",
                passed: diskInfo.sufficient,
                detail: diskInfo.detail,
                error: diskInfo.sufficient ? nil : "磁盘空间不足"
            ))
            DMLogger.log("[EnvCheck] 磁盘空间检测完成: \(diskInfo.detail), sufficient=\(diskInfo.sufficient)", name: "OnboardingViewModel")

            // gpu — 检查 GPU/硬件加速
            DMLogger.log("[EnvCheck] 开始检测 GPU 硬件加速...", name: "OnboardingViewModel")
            let gpuInfo = self.checkGPU()
            results.append(CheckResult(
                id: "gpu",
                passed: gpuInfo.available,
                detail: gpuInfo.detail,
                error: nil
            ))
            DMLogger.log("[EnvCheck] GPU 硬件加速检测完成: available=\(gpuInfo.available), detail=\(gpuInfo.detail ?? "nil")", name: "OnboardingViewModel")

            for r in results {
                DMLogger.log("  \(r.id): passed=\(r.passed), detail=\(r.detail ?? "nil"), error=\(r.error ?? "nil")", name: "OnboardingViewModel")
            }

            let hermesStatus = HermesInstallStatus(
                installed: hermesInfo.installed,
                configured: hermesInfo.configured,
                hasApiKey: hermesInfo.hasApiKey,
                hasModelConfigured: hermesInfo.hasModelConfigured,
                hermesHome: hermesInfo.hermesHome
            )

            DMLogger.log("安装状态: installed=\(hermesStatus.installed), configured=\(hermesStatus.configured), hasApiKey=\(hermesStatus.hasApiKey), hasModelConfigured=\(hermesStatus.hasModelConfigured), hermesHome=\(hermesStatus.hermesHome ?? "nil")", name: "OnboardingViewModel")

            DispatchQueue.main.async {
                completion(results, hermesStatus)
            }
        }
    }

    private func checkNetworkConnectivity() -> Bool {
        DMLogger.log("[Network] 开始检测网络连通性 (https://www.apple.com)", name: "OnboardingViewModel")
        let group = DispatchGroup()
        var isConnected = false

        guard let url = URL(string: "https://www.apple.com") else {
            DMLogger.log("[Network] URL 构造失败", name: "OnboardingViewModel")
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        group.enter()
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            defer { group.leave() }
            if let error = error {
                DMLogger.log("[Network] 请求失败: \(error.localizedDescription)", name: "OnboardingViewModel")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                isConnected = (200...299).contains(httpResponse.statusCode)
                DMLogger.log("[Network] HTTP 状态码: \(httpResponse.statusCode)", name: "OnboardingViewModel")
            }
        }
        task.resume()
        let waitResult = group.wait(timeout: .now() + 6)
        DMLogger.log("[Network] 等待结果: \(waitResult == .success ? "success" : "timedOut"), 网络检测结果: \(isConnected ? "已连接" : "未连接")", name: "OnboardingViewModel")
        return isConnected
    }

    /// 检查 Python3 是否可用。
    ///
    /// 对齐 Flutter 的 `_checkPython()`：优先检查 venv python，然后检查系统 python3。
    /// 使用文件系统检测（FileManager），避免沙盒环境下 Process() 无法执行 shell 命令的问题。
    private func checkPython(hermesHome: String? = nil) -> (available: Bool, version: String?) {
        let fm = FileManager.default

        // 1. 优先检查 venv python（对齐 Flutter: {hermesHome}/hermes-agent/venv/bin/python）
        if let home = hermesHome {
            let venvPythonPath = "\(home)/hermes-agent/venv/bin/python"
            if fm.isExecutableFile(atPath: venvPythonPath) {
                DMLogger.log("Python 检测结果: venv python 存在 \(venvPythonPath)", name: "OnboardingViewModel")
                // 尝试获取版本号（文件存在即表示可用）
                let versionOutput = runShell("'\(venvPythonPath)' --version 2>/dev/null")
                let trimmed = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                DMLogger.log("Python 检测: venv python 版本输出=\(trimmed)", name: "OnboardingViewModel")
                if !trimmed.isEmpty {
                    return (true, trimmed)
                }
                return (true, "Python 3 (venv)")
            }
        }

        // 2. 检查常见系统路径中的 python3（文件系统检测，不依赖 shell PATH）
        let knownPaths = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/opt/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
        ]

        for path in knownPaths {
            if fm.isExecutableFile(atPath: path) {
                DMLogger.log("Python 检测结果: 系统 python3 存在 \(path)", name: "OnboardingViewModel")
                let versionOutput = runShell("'\(path)' --version 2>/dev/null")
                let trimmed = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                DMLogger.log("Python 检测: 系统 python3 (\(path)) 版本输出=\(trimmed)", name: "OnboardingViewModel")
                if !trimmed.isEmpty && trimmed.contains("Python") {
                    return (true, trimmed)
                }
                return (true, "Python 3")
            }
        }

        // 3. 最后尝试 shell 命令（沙盒环境下可能失败）
        DMLogger.log("Python 检测: 最后尝试 shell python3/python --version", name: "OnboardingViewModel")
        let output = runShell("python3 --version 2>/dev/null || python --version 2>/dev/null")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let available = !trimmed.isEmpty && trimmed.contains("Python")
        DMLogger.log("Python 检测结果 (shell): available=\(available), version=\(available ? trimmed : "无")", name: "OnboardingViewModel")

        if !available {
            DMLogger.log("Python 检测结果: 未找到 Python3", name: "OnboardingViewModel")
        }
        return (available, available ? trimmed : nil)
    }

    /// 获取真实的用户 Home 目录（即使在 App Sandbox 中）。
    ///
    /// NSHomeDirectory() 在沙盒中返回容器路径（如 ~/Library/Containers/.../Data），
    /// 而 getpwuid 返回真实的 /Users/xxx 路径。
    private func realHomeDirectory() -> String {
        let pw = getpwuid(getuid())
        if let dir = pw?.pointee.pw_dir {
            return String(cString: dir)
        }
        // 回退：从 ProcessInfo 环境变量获取（通常 HOME 不受沙盒影响）
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            return home
        }
        // 最后回退：从容器路径推导真实路径（~/Library/Containers/bundleID/Data → ~/）
        let containerHome = NSHomeDirectory()
        // 容器路径格式: /Users/xxx/Library/Containers/com.x.y/Data
        let components = containerHome.split(separator: "/")
        if components.count >= 3 {
            return "/" + components[1] + "/" + components[2]
        }
        return containerHome
    }

    /// 解析 HERMES_HOME 路径。
    ///
    /// 优先级对齐 Flutter 的 `AppConstants.resolveHermesHome()`：
    /// 1. 环境变量 `HERMES_HOME`
    /// 2. 平台默认：`~/.hermes`（真实 Home，非沙盒容器）
    private func resolveHermesHome() -> String {
        // 1. 环境变量优先
        if let envHome = ProcessInfo.processInfo.environment["HERMES_HOME"], !envHome.isEmpty {
            return envHome
        }
        // 2. 默认真实 ~/.hermes
        return realHomeDirectory() + "/.hermes"
    }

    /// 检查 Hermes 引擎是否已安装。
    ///
    /// 检测策略：
    /// 1. 检查 `{hermesHome}/hermes-agent/hermes` 是否存在（使用 fileExists 而非 isExecutableFile，
    ///    后者在沙盒中可能错误返回 false）
    /// 2. 回退：检查 `~/.local/bin/hermes`（pip/uv 安装的 CLI 入口）
    /// 3. 回退：使用 shell 命令 `which hermes` 和 `hermes --version`
    func checkHermes(hermesHome: String? = nil) -> (installed: Bool, version: String?, configured: Bool, hasApiKey: Bool, hasModelConfigured: Bool, hermesHome: String?) {
        let home = hermesHome ?? resolveHermesHome()
        let fm = FileManager.default

        DMLogger.log("checkHermes: 开始检测，hermesHome=\(home)", name: "OnboardingViewModel")
        DMLogger.log("checkHermes: realHomeDirectory()=\(realHomeDirectory())", name: "OnboardingViewModel")

        // 检查 HERMES_HOME 目录是否存在
        var isDir: ObjCBool = false
        let homeExists = fm.fileExists(atPath: home, isDirectory: &isDir) && isDir.boolValue
        DMLogger.log("checkHermes: homeExists=\(homeExists), isDirectory=\(isDir.boolValue)", name: "OnboardingViewModel")

        // --- 检查 hermes 是否为已安装 ---
        // 使用 fileExists 而非 isExecutableFile（沙盒中后者可能错误返回 false）
        var installed = false
        var versionStr: String? = nil

        // 方式1：检查 {hermesHome}/hermes-agent/hermes 脚本
        let scriptPath = "\(home)/hermes-agent/hermes"
        let agentDirExists = fm.fileExists(atPath: "\(home)/hermes-agent")
        let scriptExists = fm.fileExists(atPath: scriptPath)

        DMLogger.log("checkHermes: agentDirExists=\(agentDirExists), scriptExists=\(scriptExists)", name: "OnboardingViewModel")

        if agentDirExists && scriptExists {
            installed = true
            // 尝试用 shell 获取版本号
            DMLogger.log("checkHermes: 即将执行脚本版本检测: \(scriptPath)", name: "OnboardingViewModel")
            let versionOutput = runShell("'\(scriptPath)' --version 2>/dev/null")
            let trimmed = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            DMLogger.log("checkHermes: 脚本版本检测完成, output=\(trimmed)", name: "OnboardingViewModel")
            if !trimmed.isEmpty {
                versionStr = trimmed
                DMLogger.log("checkHermes: 脚本版本: \(trimmed)", name: "OnboardingViewModel")
            }
        }

        // 方式2：检查 ~/.local/bin/hermes（pip/uv 全局安装）
        if !installed {
            let localBinPath = realHomeDirectory() + "/.local/bin/hermes"
            DMLogger.log("checkHermes: 检查 local bin: \(localBinPath)", name: "OnboardingViewModel")
            if fm.fileExists(atPath: localBinPath) {
                installed = true
                DMLogger.log("checkHermes: found \(localBinPath)", name: "OnboardingViewModel")
                let versionOutput = runShell("'\(localBinPath)' --version 2>/dev/null")
                let trimmed = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                DMLogger.log("checkHermes: local bin 版本检测完成, output=\(trimmed)", name: "OnboardingViewModel")
                if !trimmed.isEmpty { versionStr = trimmed }
            }
        }

        // 方式3：回退到 shell (which hermes / hermes --version)
        if !installed {
            DMLogger.log("checkHermes: 即将执行 which hermes", name: "OnboardingViewModel")
            let whichOutput = runShell("which hermes 2>/dev/null")
            let whichPath = whichOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            DMLogger.log("checkHermes: which hermes 完成, path=\(whichPath)", name: "OnboardingViewModel")
            if !whichPath.isEmpty {
                installed = true
                DMLogger.log("checkHermes: which hermes = \(whichPath)", name: "OnboardingViewModel")
                let versionOutput = runShell("hermes --version 2>/dev/null")
                let trimmed = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                DMLogger.log("checkHermes: hermes --version 完成, output=\(trimmed)", name: "OnboardingViewModel")
                if !trimmed.isEmpty { versionStr = trimmed }
            }
        }

        DMLogger.log("checkHermes: installed=\(installed)", name: "OnboardingViewModel")

        // --- 检查配置文件 ---
        let envPath = "\(home)/.env"
        let authPath = "\(home)/auth.json"
        let configPath = "\(home)/config.yaml"

        DMLogger.log("checkHermes: 检查配置文件路径", name: "OnboardingViewModel")
        DMLogger.log("checkHermes: envPath=\(envPath)", name: "OnboardingViewModel")
        DMLogger.log("checkHermes: authPath=\(authPath)", name: "OnboardingViewModel")
        DMLogger.log("checkHermes: configPath=\(configPath)", name: "OnboardingViewModel")

        let envExists = fm.fileExists(atPath: envPath)
        DMLogger.log("checkHermes: fm.fileExists(envPath)=\(envExists)", name: "OnboardingViewModel")

        let authExists = fm.fileExists(atPath: authPath)
        DMLogger.log("checkHermes: fm.fileExists(authPath)=\(authExists)", name: "OnboardingViewModel")

        let configExists = fm.fileExists(atPath: configPath)
        DMLogger.log("checkHermes: fm.fileExists(configPath)=\(configExists)", name: "OnboardingViewModel")

        let configured = envExists || authExists
        DMLogger.log("checkHermes: configured=\(configured)", name: "OnboardingViewModel")

        // 检查是否配置了 API key（多来源检测）
        var hasApiKey = false

        // 来源1：检查 .env 文件中的 API key
        if envExists {
            DMLogger.log("checkHermes: 尝试读取 .env 文件", name: "OnboardingViewModel")
            do {
                let envContent = try String(contentsOfFile: envPath, encoding: .utf8)
                DMLogger.log("checkHermes: .env 文件读取成功，长度=\(envContent.count)", name: "OnboardingViewModel")
                hasApiKey = parseApiKeyFromEnv(envContent)
                DMLogger.log("checkHermes: parseApiKeyFromEnv 返回 \(hasApiKey)", name: "OnboardingViewModel")
            } catch {
                DMLogger.log("checkHermes: 读取 .env 失败: \(error.localizedDescription)", name: "OnboardingViewModel")
            }
        } else {
            DMLogger.log("checkHermes: .env 文件不存在，跳过 API key 检测", name: "OnboardingViewModel")
        }

        // 来源2：检查 auth.json（OAuth/token 认证方式）
        if !hasApiKey && authExists {
            hasApiKey = true
            DMLogger.log("checkHermes: auth.json 存在，视为已配置 API key", name: "OnboardingViewModel")
        }

        // 来源3：检查 Bitwarden Secrets Manager 配置
        // 参考: https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/secrets/bitwarden
        if !hasApiKey && configExists {
            DMLogger.log("checkHermes: 检查 Bitwarden Secrets Manager 配置", name: "OnboardingViewModel")
            do {
                let configContent = try String(contentsOfFile: configPath, encoding: .utf8)
                let hasBitwardenEnabled = configContent.contains("bitwarden:")
                    && configContent.contains("enabled: true")
                let envContent = try? String(contentsOfFile: envPath, encoding: .utf8)
                let hasBwsToken = envContent?.contains("BWS_ACCESS_TOKEN=") == true
                DMLogger.log("checkHermes: hasBitwardenEnabled=\(hasBitwardenEnabled), hasBwsToken=\(hasBwsToken)", name: "OnboardingViewModel")
                if hasBitwardenEnabled && hasBwsToken {
                    hasApiKey = true
                    DMLogger.log("checkHermes: Bitwarden Secrets Manager 已配置", name: "OnboardingViewModel")
                }
            } catch {
                DMLogger.log("checkHermes: 读取 config.yaml 失败: \(error.localizedDescription)", name: "OnboardingViewModel")
            }
        }

        // 检查 config.yaml 中是否已配置默认模型
        let hasModelConfigured = checkConfigYamlForModel(hermesHome: home)

        DMLogger.log("Hermes 检测结果: installed=\(installed), configured=\(configured), hasApiKey=\(hasApiKey), hasModelConfigured=\(hasModelConfigured), hermesHome=\(home), version=\(versionStr ?? "nil")", name: "OnboardingViewModel")
        return (installed, versionStr, configured, hasApiKey, hasModelConfigured, home)
    }

    /// 从 .env 文件内容中解析是否包含有效的 API key。
    ///
    /// 对齐 Flutter 的 `_parseApiKeyFromEnv()`。
    private func parseApiKeyFromEnv(_ content: String) -> Bool {
        let lines = content.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 跳过注释和空行
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                continue
            }
            // 检查是否包含 key=value 格式且 value 非空
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                // 不是占位符且非空
                if !value.isEmpty && value.lowercased() != "your_api_key_here" && !value.hasPrefix("YOUR_") {
                    return true
                }
            }
        }
        return false
    }

    /// 检查 ~/.hermes/config.yaml 中是否已配置默认模型。
    ///
    /// 解析 config.yaml 的 model.default 字段。对齐官方文档中 config.yaml 的结构：
    ///
    ///     model:
    ///       provider: openrouter
    ///       default: anthropic/claude-opus-4.7
    ///
    /// 如果 model.default 存在且非空，则认为模型已配置。
    private func checkConfigYamlForModel(hermesHome: String) -> Bool {
        let configPath = "\(hermesHome)/config.yaml"

        DMLogger.log("checkConfigYamlForModel: configPath=\(configPath)", name: "OnboardingViewModel")

        // 优先使用 FileManager 直接读取，避免 shell cat 因管道阻塞导致超时。
        let content: String
        if let data = FileManager.default.contents(atPath: configPath),
           let str = String(data: data, encoding: .utf8), !str.isEmpty {
            content = str
            DMLogger.log("checkConfigYamlForModel: FileManager 读取结果长度=\(content.count)", name: "OnboardingViewModel")
        } else {
            DMLogger.log("checkConfigYamlForModel: FileManager 读取失败，尝试 shell 读取", name: "OnboardingViewModel")
            content = runShell("cat '\(configPath)' 2>/dev/null")
            if content.isEmpty {
                DMLogger.log("checkConfigYamlForModel: shell cat 返回空，config.yaml 不存在或无法读取", name: "OnboardingViewModel")
                return false
            }
        }

        // 打印前 500 字符用于调试
        let preview = content.prefix(500)
        DMLogger.log("checkConfigYamlForModel: 内容预览=\(preview)", name: "OnboardingViewModel")

        let result = parseYamlForModel(content: content)
        DMLogger.log("checkConfigYamlForModel: parseYamlForModel 返回 \(result)", name: "OnboardingViewModel")
        return result
    }

    /// 解析 config.yaml 内容，查找 model.default 字段
    private func parseYamlForModel(content: String) -> Bool {
        DMLogger.log("parseYamlForModel: 开始解析，内容长度=\(content.count)", name: "OnboardingViewModel")

        // 手动解析 YAML，查找 model: 块下的 default: 字段
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var inModelSection = false

        for line in lines {
            let raw = String(line)
            let trimmedLine = raw.trimmingCharacters(in: .whitespaces)

            // 跳过空行和注释
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            // 判断原始行是否有缩进（子字段）
            let isIndented = raw.hasPrefix(" ") || raw.hasPrefix("\t")

            if !inModelSection {
                // 查找顶层 model: key（无缩进）
                if !isIndented && (trimmedLine == "model:" || trimmedLine.hasPrefix("model:")) {
                    inModelSection = true
                    DMLogger.log("checkConfigYamlForModel: 进入 model: section", name: "OnboardingViewModel")
                }
            } else {
                // 在 model: section 内
                if !isIndented {
                    // 遇到新的顶层 key，退出 model section
                    DMLogger.log("checkConfigYamlForModel: 遇到顶层 key '\(trimmedLine)'，退出 model section", name: "OnboardingViewModel")
                    inModelSection = false
                    continue
                }

                // 查找 default: <value>（model 的子字段）
                if trimmedLine.hasPrefix("default:") {
                    let parts = trimmedLine.split(separator: ":", maxSplits: 1)
                    if parts.count >= 2 {
                        let value = parts[1].trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        if !value.isEmpty {
                            DMLogger.log("checkConfigYamlForModel: 找到默认模型 '\(value)'", name: "OnboardingViewModel")
                            return true
                        }
                    }
                }
            }
        }

        DMLogger.log("checkConfigYamlForModel: 未找到有效的 model.default 配置", name: "OnboardingViewModel")
        return false
    }

    private func checkDiskSpace() -> (sufficient: Bool, detail: String) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeSize = attrs[.systemFreeSize] as? Int64 else {
            return (false, "无法检测")
        }
        let freeGB = Double(freeSize) / 1_073_741_824.0
        let sufficient = freeGB >= 2.0
        let detail = String(format: "%.1f GB 可用", freeGB)
        DMLogger.log("磁盘空间: \(detail), sufficient=\(sufficient)", name: "OnboardingViewModel")
        return (sufficient, detail)
    }

    private func checkGPU() -> (available: Bool, detail: String?) {
        // 通过 system_profiler 获取 GPU 信息
        DMLogger.log("GPU 检测: 开始执行 system_profiler", name: "OnboardingViewModel")
        let output = runShell("system_profiler SPDisplaysDataType 2>/dev/null | grep 'Chipset Model' | awk -F': ' '{print $2}'")
        let gpuName = output.trimmingCharacters(in: .whitespacesAndNewlines)
        DMLogger.log("GPU 检测: system_profiler 输出=\(gpuName)", name: "OnboardingViewModel")
        if !gpuName.isEmpty {
            DMLogger.log("GPU 检测结果: \(gpuName)", name: "OnboardingViewModel")
            return (true, gpuName)
        }

        // 回退：检查 Apple Silicon
        var sysInfo = utsname()
        uname(&sysInfo)
        let machine = withUnsafePointer(to: &sysInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        DMLogger.log("GPU 检测结果 (回退): Apple \(machine)", name: "OnboardingViewModel")
        return (!machine.isEmpty, "Apple \(machine)")
    }

    private func runShell(_ command: String, timeout: TimeInterval = 10) -> String {
        DMLogger.log("[runShell] 开始执行 (timeout=\(timeout)s): \(command)", name: "OnboardingViewModel")
        let start = Date()

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        // 使用 readabilityHandler 异步累积输出，避免超时后 readDataToEndOfFile 阻塞。
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
            DMLogger.log("[runShell] 启动失败: \(error.localizedDescription), command=\(command)", name: "OnboardingViewModel")
            pipeHandle.readabilityHandler = nil
            return ""
        }

        // 在后台等待进程退出，避免 waitUntilExit 永远阻塞当前线程
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            task.waitUntilExit()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            DMLogger.log("[runShell] 超时 \(timeout)s，终止任务: \(command)", name: "OnboardingViewModel")
            task.terminate()
            _ = group.wait(timeout: .now() + 2)
        }

        // 移除 handler 并关闭读取端，确保后续不再阻塞。
        pipeHandle.readabilityHandler = nil
        try? pipeHandle.close()

        outputLock.lock()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        outputLock.unlock()

        let elapsed = Date().timeIntervalSince(start)
        DMLogger.log("[runShell] 完成: 耗时=\(String(format: "%.2f", elapsed))s, 退出码=\(task.terminationStatus), 输出长度=\(output.count), command=\(command)", name: "OnboardingViewModel")
        return output
    }

    /// 使用 shell 检测文件是否存在（沙盒环境下 FileManager 可能无法访问 ~/.hermes/）
    private func shellFileExists(_ path: String) -> Bool {
        let output = runShell("test -f '\(path)' && echo 'exists' || echo 'not_found'")
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "exists"
    }

    // MARK: - Step 2: Install Engine

    /// 开始真实的 Hermes 安装（对齐 Flutter 的 startInstallation）。
    func startInstallation(mirrorUrl: String? = nil) {
        DMLogger.log("[OnboardingVM] startInstallation 开始安装: mirrorUrl=\(mirrorUrl ?? "nil")", name: "OnboardingViewModel")
        installStartTime = Date()

        setCancelled(false)
        installMilestone = 0.0
        lastMilestoneTime = installStartTime
        lastMilestoneValue = 0.0
        setInstallProcess(nil)

        model.isInstalling = true
        model.isInstallFailed = false
        model.installError = nil
        model.isDownloadSlow = false
        model.showMirrorPrompt = false
        model.showInitialMirrorPrompt = false
        model.installStartTime = installStartTime
        model.mirrorUrl = mirrorUrl
        model.downloadProgress = 0.0
        model.downloadSpeed = "准备中"
        model.estimatedTime = "-- s"
        model.installStageLabel = "准备开始..."
        model.currentDownloadingItem = nil
        model.installLogTail = nil

        DMLogger.log("[OnboardingVM] 启动慢速下载检测计时器 (\(Int(kSlowDownloadTimeoutSeconds))秒)", name: "OnboardingViewModel")
        startSlowDownloadDetection()

        // 在后台运行真实安装（官方 install.sh + 流式输出）
        // 使用 Task.detached 避免继承主 actor，否则 runShell 中的 waitUntilExit 会阻塞主线程导致 UI 卡死。
        Task.detached { [weak self] in
            await self?.runInstallation(mirrorUrl: mirrorUrl)
        }
    }

    /// 真实安装流程：运行官方 install.sh，流式读取输出驱动进度。
    ///
    /// 成功判定：进程退出码 0 且 `checkHermes()` 验证通过；二者任一不满足即 `failInstall`，
    /// 不置进度为 1.0，不放行 `canAdvance`，错误横幅出现。
    ///
    /// 镜像通过进程级 git `insteadOf` 环境变量注入子进程，不写入 `~/.gitconfig`。
    private func runInstallation(mirrorUrl: String?) async {
        let hermesHome = resolveHermesHome()

        // ---- 阶段 0: 已安装则跳过 ----
        reportMilestone(0.05, stage: "正在检查前置依赖...", item: "检测 Hermes 是否已安装")
        DMLogger.log("[OnboardingVM] 阶段0: 检查 Hermes 是否已安装", name: "OnboardingViewModel")

        if checkHermes(hermesHome: hermesHome).installed {
            DMLogger.log("[OnboardingVM] Hermes 已安装，跳过安装流程", name: "OnboardingViewModel")
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.slowDownloadTimer?.invalidate()
                self.installMilestone = 1.0
                self.model.downloadProgress = 1.0
                self.model.isInstalling = false
                self.model.installStageLabel = "已安装（无需重复安装）"
                self.model.downloadSpeed = "就绪"
                self.model.estimatedTime = "-- s"
                self.model.hermesInstalled = true
                self.model.isDownloadSlow = false
                self.model.showMirrorPrompt = false
                self.model.currentDownloadingItem = nil
            }
            return
        }

        // ---- 阶段 1: 官方脚本要求 git 可用 ----
        let gitOut = runShell("git --version 2>/dev/null")
        let gitOk = !gitOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        DMLogger.log("[OnboardingVM] 阶段1: git 检测 gitOk=\(gitOk)", name: "OnboardingViewModel")
        guard gitOk else {
            failInstall("未检测到 git。请先在终端运行 `xcode-select --install` 安装 Xcode Command Line Tools 后重试。")
            return
        }
        reportMilestone(0.10, stage: "准备官方安装脚本", item: "git 已就绪 ✓")

        // ---- 阶段 1.5: 预置 managed uv 符号链接 ----
        // install.sh 的 install_uv() 总是把 uv 装到 ~/.hermes/bin/uv。
        // astral.sh 的 uv 安装器在系统已有 uv 时 exit 0 但不放置二进制，
        // 导致 "uv installer reported success but binary not found"。
        // 解决：系统已有 uv 时预先创建符号链接，让 install_uv() 直接复用。
        precreateManagedUvSymlink(hermesHome: hermesHome)

        // ---- 阶段 2: 构造镜像环境（进程级 git insteadOf，非全局 config）----
        var env = ProcessInfo.processInfo.environment

        // 扩展 PATH：macOS app 从 Finder 启动时 PATH 只有 /usr/bin:/bin，
        // 缺少 ~/.local/bin、/opt/homebrew/bin 等，导致 install.sh 找不到 node/uv/python3。
        let userHome = NSHomeDirectory()
        var expandedPath = env["PATH"] ?? "/usr/bin:/bin"
        for entry in ["\(userHome)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"].reversed() {
            if !expandedPath.contains(entry) {
                expandedPath = "\(entry):\(expandedPath)"
            }
        }
        // nvm 管理的 node 路径（版本号不固定，取最新）
        let nvmNodeBin = runShell("ls -d \(userHome)/.nvm/versions/node/*/bin 2>/dev/null | tail -1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !nvmNodeBin.isEmpty && !expandedPath.contains(nvmNodeBin) {
            expandedPath = "\(nvmNodeBin):\(expandedPath)"
        }
        env["PATH"] = expandedPath
        DMLogger.log("[OnboardingVM] 扩展后 PATH=\(expandedPath)", name: "OnboardingViewModel")

        let useMirror = mirrorUrl != nil && !mirrorUrl!.isEmpty
        let installScriptUrl = useMirror ? kHermesChinaInstallUrl : kHermesOfficialInstallUrl

        if useMirror, let mirror = mirrorUrl {
            // git ≥2.31 支持 GIT_CONFIG_COUNT / GIT_CONFIG_KEY_n / GIT_CONFIG_VALUE_n
            // 把 https://github.com/... 重写为 <mirror>...
            env["GIT_CONFIG_COUNT"] = "1"
            env["GIT_CONFIG_KEY_0"] = "url.\(mirror).insteadOf"
            env["GIT_CONFIG_VALUE_0"] = "https://github.com/"
            // pip / uv 国内镜像加速 Python 依赖下载
            env["PIP_INDEX_URL"] = kDefaultPipIndexUrl
            env["UV_INDEX_URL"] = kDefaultPipIndexUrl
            env["PIP_TRUSTED_HOST"] = "pypi.tuna.tsinghua.edu.cn"
            DMLogger.log("[OnboardingVM] 已注入进程级国内镜像: git=\(mirror), pip=\(kDefaultPipIndexUrl)", name: "OnboardingViewModel")
        }

        // ---- 阶段 3: 流式运行官方安装脚本 ----
        // 不加 `< /dev/null`：那会覆盖 `curl | bash` 的管道输入，导致 bash 读到空脚本。
        // 脚本自身用 `[ -t 0 ]` 检测非交互模式——管道 stdin 非 tty → IS_INTERACTIVE=false。
        // --skip-setup 跳过交互式 setup 向导（模型配置由第 3 步 onboarding 负责）；
        // --non-interactive 跳过需要用户输入的阶段（如 sudo 提示）。
        reportMilestone(0.15, stage: "正在运行官方安装脚本", item: "拉取并执行 install.sh")
        let argv = "curl -fsSL \(installScriptUrl) | bash -s -- --skip-setup --non-interactive"
        DMLogger.log("[OnboardingVM] 阶段3: 运行官方安装脚本", name: "OnboardingViewModel")

        do {
            let result = try await StreamingProcessRunner.run(
                executable: "/bin/bash",
                args: ["-c", argv],
                environment: env,
                timeout: 30 * 60,   // 安装较重，给 30 分钟
                logName: "OnboardingViewModel",
                onOutput: { [weak self] tail in
                    self?.handleInstallOutput(tail)
                },
                onProcessReady: { [weak self] proc in
                    self?.setInstallProcess(proc)
                }
            )
            setInstallProcess(nil)

            // 官方 install.sh 未把 aiohttp 装入 venv，会导致 Gateway API server 无法启动，
            // 因此在 install.sh 成功后显式补充安装。
            await installAiohttpIfNeeded(hermesHome: hermesHome, useMirror: useMirror)

            finishInstall(result: result, hermesHome: hermesHome)
        } catch {
            setInstallProcess(nil)
            DMLogger.error("[OnboardingVM] 启动安装脚本失败: \(error)", name: "OnboardingViewModel")
            if !getCancelled() {
                failInstall("启动安装脚本失败：\(error.localizedDescription)")
            }
        }
    }

    /// 官方 install.sh 没有安装 aiohttp，导致 Gateway API server 无法启动。
    /// 在 install.sh 成功后显式补充安装到 Hermes venv，并沿用用户选择的国内镜像。
    ///
    /// 兼容 uv 创建的 venv（无 pip）：优先用 venv pip，否则用系统 uv，
    /// 再兜底尝试 ensurepip。所有命令保留 stderr，便于诊断失败原因。
    private func installAiohttpIfNeeded(hermesHome: String, useMirror: Bool) async {
        let venvPip = "\(hermesHome)/hermes-agent/venv/bin/pip"
        let venvPython = "\(hermesHome)/hermes-agent/venv/bin/python"
        let fm = FileManager.default

        await MainActor.run { [weak self] in
            self?.model.installStageLabel = "正在安装 Gateway 网络依赖..."
            self?.model.currentDownloadingItem = "aiohttp"
        }

        // 1) venv pip 可用：直接用 pip install
        if fm.isExecutableFile(atPath: venvPip),
           runShell("'\(venvPip)' --version 2>&1").lowercased().contains("pip") {
            let base = "'\(venvPip)' install aiohttp"
            let command = useMirror
                ? "PIP_INDEX_URL='\(kDefaultPipIndexUrl)' PIP_TRUSTED_HOST='pypi.tuna.tsinghua.edu.cn' \(base)"
                : base
            DMLogger.log("[OnboardingVM] installAiohttpIfNeeded (venv pip): \(command)", name: "OnboardingViewModel")
            let output = runShell(command, timeout: 120)
            DMLogger.log("[OnboardingVM] installAiohttpIfNeeded (venv pip) 完成，输出长度=\(output.count)", name: "OnboardingViewModel")
            return
        }

        // 2) venv 由 uv 创建，无 pip：使用系统 uv 安装到该 venv
        let systemUvCandidates = [
            NSHomeDirectory() + "/.local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv"
        ]
        if let systemUv = systemUvCandidates.first(where: { fm.isExecutableFile(atPath: $0) }),
           runShell("'\(systemUv)' --version 2>&1").lowercased().contains("uv") {
            let base = "'\(systemUv)' pip install --python '\(venvPython)' aiohttp"
            let command = useMirror
                ? "UV_INDEX_URL='\(kDefaultPipIndexUrl)' \(base)"
                : base
            DMLogger.log("[OnboardingVM] installAiohttpIfNeeded (uv): \(command)", name: "OnboardingViewModel")
            let output = runShell(command, timeout: 120)
            DMLogger.log("[OnboardingVM] installAiohttpIfNeeded (uv) 完成，输出长度=\(output.count)", name: "OnboardingViewModel")
            return
        }

        // 3) 兜底：venv python + ensurepip，再安装 aiohttp
        guard fm.isExecutableFile(atPath: venvPython) else {
            DMLogger.log("[OnboardingVM] installAiohttpIfNeeded: 未找到 venv python，跳过", name: "OnboardingViewModel")
            return
        }
        DMLogger.log("[OnboardingVM] installAiohttpIfNeeded: 尝试 ensurepip 安装 pip", name: "OnboardingViewModel")
        let ensurepipOutput = runShell("'\(venvPython)' -m ensurepip --default-pip 2>&1", timeout: 120)
        DMLogger.log("[OnboardingVM] installAiohttpIfNeeded ensurepip 输出长度=\(ensurepipOutput.count)", name: "OnboardingViewModel")

        let base = "'\(venvPython)' -m pip install aiohttp"
        let command = useMirror
            ? "PIP_INDEX_URL='\(kDefaultPipIndexUrl)' PIP_TRUSTED_HOST='pypi.tuna.tsinghua.edu.cn' \(base)"
            : base
        DMLogger.log("[OnboardingVM] installAiohttpIfNeeded (ensurepip fallback): \(command)", name: "OnboardingViewModel")
        let output = runShell(command, timeout: 120)
        DMLogger.log("[OnboardingVM] installAiohttpIfNeeded (ensurepip fallback) 完成，输出长度=\(output.count)", name: "OnboardingViewModel")
    }

    /// 预置 ~/.hermes/bin/uv 符号链接，绕过 astral.sh 安装器在系统已有 uv 时的 bug
    /// （安装器 exit 0 但不放置二进制，导致 install.sh 报 "binary not found" 退出）。
    private func precreateManagedUvSymlink(hermesHome: String) {
        let managedUvPath = "\(hermesHome)/bin/uv"
        let fm = FileManager.default

        if fm.isExecutableFile(atPath: managedUvPath) {
            DMLogger.log("[OnboardingVM] managed uv 已存在: \(managedUvPath)", name: "OnboardingViewModel")
            return
        }

        let userHome = NSHomeDirectory()
        let candidates = [
            "\(userHome)/.local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv"
        ]
        guard let systemUv = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            DMLogger.log("[OnboardingVM] 系统未安装 uv，install.sh 将自行下载安装", name: "OnboardingViewModel")
            return
        }

        let binDir = "\(hermesHome)/bin"
        do {
            try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        } catch {
            DMLogger.error("[OnboardingVM] 创建 \(binDir) 失败: \(error)", name: "OnboardingViewModel")
            return
        }
        try? fm.removeItem(atPath: managedUvPath)
        do {
            try fm.createSymbolicLink(atPath: managedUvPath, withDestinationPath: systemUv)
            DMLogger.log("[OnboardingVM] 已预置 uv 符号链接: \(managedUvPath) -> \(systemUv)", name: "OnboardingViewModel")
        } catch {
            DMLogger.error("[OnboardingVM] 创建 uv 符号链接失败: \(error)", name: "OnboardingViewModel")
        }
    }

    /// 处理流式输出的尾部日志：剥离 ANSI、匹配关键字驱动单调进度、更新 UI 实时文本。
    /// 在 `OutputTicker` 后台队列触发；所有 `@Published` 写入走主线程。
    private func handleInstallOutput(_ tail: String) {
        let cleaned = StreamingProcessRunner.stripANSI(tail)
        let lines = cleaned.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return }

        let lastLine = lines.last ?? ""
        let logTail = StreamingProcessRunner.lastNonEmptyLines(in: cleaned, max: 8)

        // 计算本批输出命中的最高 milestone（单调递增）
        var candidate: Double = 0.0
        for line in lines {
            let hit = milestoneForLine(line)
            if hit > candidate { candidate = hit }
        }

        let elapsed = Int(Date().timeIntervalSince(installStartTime))
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.model.currentDownloadingItem = lastLine
            self.model.installLogTail = logTail
            self.model.downloadSpeed = "实时安装中"
            self.model.estimatedTime = "已用 \(elapsed)s"

            let newMilestone = max(candidate, self.installMilestone)
            if newMilestone > self.installMilestone {
                self.installMilestone = newMilestone
                self.lastMilestoneTime = Date()
                self.lastMilestoneValue = newMilestone
                self.model.downloadProgress = newMilestone
                self.model.installStageLabel = Self.milestoneStageLabel(newMilestone)
                DMLogger.log("[OnboardingVM] 进度推进到 \(newMilestone), item=\(lastLine)", name: "OnboardingViewModel")
                // 进度越过阈值后取消慢速检测
                if newMilestone > kSlowDownloadProgressThreshold {
                    self.slowDownloadTimer?.invalidate()
                    if self.model.isDownloadSlow {
                        self.model.isDownloadSlow = false
                        DMLogger.log("[OnboardingVM] 下载已加速，隐藏慢速提示", name: "OnboardingViewModel")
                    }
                }
            } else {
                // 长时间未命中新 milestone 时，在当前区间内平滑前进，避免进度条卡住。
                let timeSinceMilestone = Date().timeIntervalSince(self.lastMilestoneTime)
                let smoothed = Self.smoothProgress(base: self.lastMilestoneValue, elapsed: timeSinceMilestone)
                if smoothed > self.model.downloadProgress {
                    self.model.downloadProgress = smoothed
                }
            }
        }
    }

    /// 根据输出行关键字返回对应的 milestone（0 表示不匹配）。
    /// 大小写不敏感；进度单调递增由调用方保证。
    private func milestoneForLine(_ raw: String) -> Double {
        let line = raw.lowercased()
        // 最终完成/验证阶段：必须放在最前，避免被后面的 "installing" 等误截获
        if (line.contains("complete") && (line.contains("install") || line.contains("hermes")))
            || line.contains("installation successful")
            || line.contains("hermes installed")
            || line.contains("symlink") || line.contains("added to path")
            || line.contains("✓ hermes") || line.contains("✓ install") {
            return 0.95
        }
        // 浏览器/Node/多媒体工具依赖
        if line.contains("playwright") || line.contains("chromium") || line.contains("browser")
            || line.contains("ripgrep") || line.contains("ffmpeg")
            || line.contains("npm install") || line.contains("node_modules") {
            return 0.90
        }
        // Node/npm 准备
        if line.contains("node") || line.contains("npm") || line.contains("npx") {
            return 0.80
        }
        // Python 依赖安装
        if line.contains("pip install") || line.contains("requirements")
            || line.contains("resolving dependencies") || line.contains("dependencies installed")
            || (line.contains("installing") && (line.contains("python") || line.contains("package"))) {
            return 0.70
        }
        // Python venv / uv 环境创建
        if line.contains("creating venv") || line.contains("venv created")
            || line.contains("virtual environment") || line.contains("uv sync")
            || line.contains("uv venv") || line.contains("python 3.11") || line.contains("python3.11") {
            return 0.55
        }
        // 仓库克隆完成
        if line.contains("cloned") || line.contains("clone complete")
            || line.contains("repository ready") || line.contains("done cloning") {
            return 0.35
        }
        // 仓库克隆/下载
        if line.contains("cloning") || line.contains("git clone")
            || line.contains("download hermes") || line.contains("fetching repository")
            || line.contains("repository") {
            return 0.15
        }
        return 0.0
    }

    /// 在当前 milestone 区间内做基于时间的平滑增长，避免进度条长时间停滞。
    private static func smoothProgress(base: Double, elapsed: TimeInterval) -> Double {
        let milestones = progressMilestones
        guard let upperIndex = milestones.firstIndex(where: { $0 > base }), upperIndex > 0 else {
            return base
        }
        let upper = milestones[upperIndex]
        let range = upper - base
        // 每 30 秒在当前区间内前进 80%，接近下一 milestone 但不超过它。
        let fillRatio = min(elapsed / 30.0, 1.0) * 0.8
        return min(base + range * fillRatio, upper - 0.001)
    }

    /// 安装脚本结束后的成败判定。
    private func finishInstall(result: StreamingProcessRunner.Result, hermesHome: String) {
        // 用户已取消：静默重置，不报失败
        if getCancelled() {
            DMLogger.log("[OnboardingVM] 安装已被用户取消，静默重置", name: "OnboardingViewModel")
            DispatchQueue.main.async { [weak self] in self?.resetInstallState() }
            return
        }

        DMLogger.log("[OnboardingVM] 安装脚本结束 exitCode=\(result.exitCode), stdout=\(result.stdout.count)B, stderr=\(result.stderr.count)B", name: "OnboardingViewModel")

        if result.exitCode == 0 {
            // 退出码 0 还需二次验证 hermes 可执行文件确实生成
            let installed = checkHermes(hermesHome: hermesHome).installed
            if installed {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.slowDownloadTimer?.invalidate()
                    self.installMilestone = 1.0
                    self.model.downloadProgress = 1.0
                    self.model.isInstalling = false
                    self.model.installStageLabel = "安装完成 ✓"
                    self.model.downloadSpeed = "就绪"
                    self.model.estimatedTime = "-- s"
                    self.model.hermesInstalled = true
                    self.model.isDownloadSlow = false
                    self.model.showMirrorPrompt = false
                    self.model.currentDownloadingItem = nil
                    DMLogger.log("[OnboardingVM] 安装成功!", name: "OnboardingViewModel")
                    // 重新检测环境以刷新状态
                    self.startEnvironmentCheck()
                }
                return
            }
            failInstall("安装脚本退出码为 0，但未检测到 hermes 可执行文件。\n\(Self.tailOf(result))")
        } else {
            failInstall("安装失败（退出码 \(result.exitCode)）。\n\(Self.tailOf(result))")
        }
    }

    /// 标记安装失败：置 `isInstallFailed`、显示错误横幅、**不置进度为 1.0**（保留当前 milestone < 1.0 → canAdvance=false）。
    private func failInstall(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.slowDownloadTimer?.invalidate()
            self.model.isInstalling = false
            self.model.isInstallFailed = true
            self.model.installError = message
            self.model.installStageLabel = "安装失败"
            self.model.downloadSpeed = "安装失败"
            DMLogger.error("[OnboardingVM] 安装失败: \(message)", name: "OnboardingViewModel")
        }
    }

    /// 重置安装中间状态（取消后使用）。
    private func resetInstallState() {
        slowDownloadTimer?.invalidate()
        model.isInstalling = false
        model.downloadProgress = 0.0
        model.isDownloadSlow = false
        model.showMirrorPrompt = false
        model.currentDownloadingItem = nil
        model.installLogTail = nil
        installMilestone = 0.0
    }

    /// 取结果末尾若干非空行作为错误上下文（已剥离 ANSI）。
    private static func tailOf(_ result: StreamingProcessRunner.Result) -> String {
        let combined = StreamingProcessRunner.stripANSI(result.stdout + "\n" + result.stderr)
        return StreamingProcessRunner.lastNonEmptyLines(in: combined, max: 10)
    }

    /// milestone 档位 → 中文阶段名。
    private static func milestoneStageLabel(_ m: Double) -> String {
        switch m {
        case 0.95...: return "正在完成安装验证"
        case 0.85..<0.95: return "正在安装 Node/浏览器工具依赖"
        case 0.70..<0.85: return "正在安装 Python 依赖"
        case 0.40..<0.70: return "正在配置 Python 环境"
        case 0.15..<0.40: return "正在下载 Hermes Agent 仓库"
        default: return "正在运行官方安装脚本"
        }
    }

    /// 报告一个显式 milestone（来自 runInstallation 的阶段标记），单调递增，无 sleep、无假 ETA。
    private func reportMilestone(_ progress: Double, stage: String, item: String) {
        let elapsed = Int(Date().timeIntervalSince(installStartTime))
        DMLogger.log("[OnboardingVM] milestone=\(progress), stage=\(stage), item=\(item)", name: "OnboardingViewModel")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if progress > self.installMilestone {
                self.installMilestone = progress
                self.lastMilestoneTime = Date()
                self.lastMilestoneValue = progress
                self.model.downloadProgress = progress
            }
            self.model.installStageLabel = stage
            self.model.downloadSpeed = "实时安装中"
            self.model.estimatedTime = "已用 \(elapsed)s"
            self.model.currentDownloadingItem = item
            if progress > kSlowDownloadProgressThreshold {
                self.slowDownloadTimer?.invalidate()
                if self.model.isDownloadSlow {
                    self.model.isDownloadSlow = false
                }
            }
        }
    }

    /// 启动慢速下载检测计时器（对齐 Flutter 的 _startSlowDownloadDetection）。
    private func startSlowDownloadDetection() {
        slowDownloadTimer?.invalidate()
        slowDownloadTimer = Timer.scheduledTimer(
            withTimeInterval: kSlowDownloadTimeoutSeconds,
            repeats: false
        ) { [weak self] _ in
            guard let self = self else { return }
            DMLogger.log("[OnboardingVM] 慢速下载检测触发: progress=\(String(format: "%.3f", self.model.downloadProgress)), elapsed=\(String(format: "%.0f", Date().timeIntervalSince(self.installStartTime)))s, isInstalling=\(self.model.isInstalling), mirrorUrl=\(self.model.mirrorUrl ?? "nil")", name: "OnboardingViewModel")

            if self.model.isInstalling &&
                self.model.downloadProgress < kSlowDownloadProgressThreshold &&
                !self.model.isInstallFailed &&
                self.model.mirrorUrl == nil {
                self.model.isDownloadSlow = true
                self.model.showMirrorPrompt = true
                DMLogger.log("[OnboardingVM] 显示镜像加速提示: 下载速度过慢, 已超过\(Int(kSlowDownloadTimeoutSeconds))秒但进度仅\(String(format: "%.1f", self.model.downloadProgress * 100))%", name: "OnboardingViewModel")
            }
        }
    }

    /// 配置 GitHub 国内镜像并重新开始安装（对齐 Flutter 的 configureMirrorAndRestart）。
    func configureMirrorAndRestart() {
        DMLogger.log("[OnboardingVM] configureMirrorAndRestart: 用户确认配置镜像加速", name: "OnboardingViewModel")

        model.isConfiguringMirror = true
        model.showMirrorPrompt = false
        model.installStageLabel = "正在配置镜像加速..."

        let mirrorUrl = kDefaultGithubMirror
        DMLogger.log("[OnboardingVM] 使用的镜像地址: \(mirrorUrl)", name: "OnboardingViewModel")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.model.isConfiguringMirror = false
            self.model.mirrorUrl = mirrorUrl

            DMLogger.log("[OnboardingVM] 使用镜像重新开始下载...", name: "OnboardingViewModel")
            self.startInstallation(mirrorUrl: mirrorUrl)
        }
    }

    /// 关闭镜像提示，不配置镜像，继续当前速度下载。
    func dismissMirrorPrompt() {
        DMLogger.log("[OnboardingVM] dismissMirrorPrompt: 用户选择继续等待，不配置镜像", name: "OnboardingViewModel")
        model.showMirrorPrompt = false
    }

    // MARK: - Initial Mirror Prompt

    /// 环境检测后发现缺少依赖，弹出 Alert 让用户选择使用国内镜像还是官方地址。
    func promptForMirrorThenInstall() {
        DMLogger.log("[OnboardingVM] promptForMirrorThenInstall: 显示镜像选择弹窗", name: "OnboardingViewModel")
        model.showInitialMirrorPrompt = true
    }

    /// 用户在国内镜像弹窗中做出选择后开始安装。
    func startInstallationWithMirrorChoice(useMirror: Bool) {
        let mirrorUrl = useMirror ? kDefaultGithubMirror : nil
        DMLogger.log("[OnboardingVM] startInstallationWithMirrorChoice: useMirror=\(useMirror), mirrorUrl=\(mirrorUrl ?? "nil")", name: "OnboardingViewModel")
        model.showInitialMirrorPrompt = false
        startInstallation(mirrorUrl: mirrorUrl)
    }

    /// 取消正在进行的下载/安装：真正终止 install.sh 子进程，并给出可重试状态。
    func cancelDownload() {
        DMLogger.log("[OnboardingVM] cancelDownload: 用户取消了下载", name: "OnboardingViewModel")
        setCancelled(true)
        getInstallProcess()?.terminate()
        setInstallProcess(nil)
        downloadTimer?.invalidate()
        slowDownloadTimer?.invalidate()
        installMilestone = 0.0
        model.isInstalling = false
        model.downloadProgress = 0.0
        model.isDownloadSlow = false
        model.showMirrorPrompt = false
        model.currentDownloadingItem = nil
        model.installLogTail = nil
        // 视为可重试状态，复用错误横幅的"重试"按钮，避免取消后卡死无路可走
        model.isInstallFailed = true
        model.installError = "安装已取消，可点击重试重新开始。"
        model.installStageLabel = "已取消"
        model.downloadSpeed = "已取消"
    }

    /// 安装失败后重试。
    func retryInstallation() {
        DMLogger.log("[OnboardingVM] retryInstallation: 用户重试安装, mirrorUrl=\(model.mirrorUrl ?? "nil")", name: "OnboardingViewModel")
        setCancelled(false)
        installMilestone = 0.0
        setInstallProcess(nil)
        model.isInstallFailed = false
        model.installError = nil
        model.downloadProgress = 0.0
        model.isDownloadSlow = false
        model.showMirrorPrompt = false
        model.showInitialMirrorPrompt = false
        model.currentDownloadingItem = nil
        model.installLogTail = nil
        startInstallation(mirrorUrl: model.mirrorUrl)
    }

    // MARK: - Step 3: Welcome Guide (配置大模型)

    /// 选择 AI 模型。
    func selectAiModel(_ modelId: String) {
        model.selectedAiModel = modelId
    }

    /// 设置模型供应商类型 ('builtin' 或 'custom')。
    func setModelProviderType(_ type: String) {
        model.modelProviderType = type
    }

    /// 选择内置模型供应商。
    func selectBuiltInProvider(_ providerId: String) {
        model.selectedBuiltInProvider = providerId
    }

    /// 设置内置供应商的模型 ID。
    func setBuiltInModelId(_ modelId: String) {
        model.selectedBuiltInModelId = modelId
    }

    /// 设置自定义模型 ID。
    func setCustomModelId(_ modelId: String) {
        model.customModelId = modelId
    }

    /// 设置自定义模型请求 URL。
    func setCustomModelUrl(_ url: String) {
        model.customModelUrl = url
    }

    /// 设置自定义供应商名称。
    func setCustomProviderName(_ name: String) {
        model.customProviderName = name
    }

    /// 设置 API Key。
    func setApiKey(_ key: String) {
        model.apiKey = key
    }

    /// 设置宠物性格文件（兼容旧字段，实际 personality 由 SOUL.md 控制）。
    func setPetPersonalityFile(_ fileName: String?) {
        model.petPersonalityFile = fileName
    }

    /// 读取当前 ~/.hermes/SOUL.md 内容到 model。
    func loadSoulFile() {
        guard !model.isSoulFileLoading else { return }
        model.isSoulFileLoading = true
        model.soulFileError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let content = try MemoryFileStore().readSoulFile()
                DispatchQueue.main.async {
                    self.model.soulFileContent = content
                    self.model.isSoulFileLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.model.soulFileContent = nil
                    self.model.soulFileError = error.localizedDescription
                    self.model.isSoulFileLoading = false
                    DMLogger.error("读取 SOUL.md 失败: \(error.localizedDescription)", name: "OnboardingViewModel")
                }
            }
        }
    }

    /// 用户选择了一个本地 .md 文件，校验格式并立即替换 SOUL.md。
    func selectSoulFile(_ url: URL) {
        guard url.pathExtension.lowercased() == "md" else {
            model.soulFileError = "仅支持 .md 格式的文件"
            DMLogger.log("用户选择了非 md 文件: \(url.pathExtension)", name: "OnboardingViewModel")
            return
        }
        model.soulFileURL = url
        model.soulFileError = nil
        replaceSoulFile(with: url)
    }

    /// 清除用户选择的 SOUL.md 替换文件。
    func clearSoulFile() {
        model.soulFileURL = nil
        model.petPersonalityFile = nil
        model.soulFileError = nil
    }

    /// 显示/隐藏 SOUL.md 内容预览弹窗。
    func toggleSoulPreview() {
        model.showSoulPreview.toggle()
    }

    /// 将用户选择的 .md 文件内容写入 ~/.hermes/SOUL.md。
    private func replaceSoulFile(with url: URL) {
        model.isSoulFileLoading = true
        model.soulFileError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                try MemoryFileStore().writeSoulFile(content)
                DispatchQueue.main.async {
                    self.model.soulFileContent = content
                    self.model.petPersonalityFile = url.lastPathComponent
                    self.model.isSoulFileLoading = false
                    self.model.soulFileError = nil
                    DMLogger.log("SOUL.md 已通过 onboarding 替换为: \(url.path)", name: "OnboardingViewModel")
                }
            } catch {
                DispatchQueue.main.async {
                    self.model.isSoulFileLoading = false
                    self.model.soulFileError = "替换 SOUL.md 失败: \(error.localizedDescription)"
                    DMLogger.error("替换 SOUL.md 失败: \(error.localizedDescription)", name: "OnboardingViewModel")
                }
            }
        }
    }

    // MARK: - Complete Onboarding

    /// 完成 onboarding：保存配置并标记为已完成（对齐 Flutter 的 completeOnboarding）。
    ///
    /// 完整流程（修复：原实现只保存 desktop.json，未真正写入模型配置和 API Key）：
    ///   1. 持久化 desktop.json（保留 githubMirror 等已存在字段）
    ///   2. **如果用户在引导中配置了模型**，将 provider/model 写入 `config.yaml` 的 model 块
    ///   3. **如果用户输入了 API Key**，将其写入 `~/.hermes/.env`
    ///   4. 首次启动时写入 agent 块（包含 personalities）
    ///   5. 重启 Gateway 让新配置生效
    func completeOnboarding() {
        DMLogger.log("completeOnboarding called", name: "OnboardingViewModel")

        model.isSaving = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. 保存桌面配置（desktop.json）
            self.saveDesktopConfig()

            // 2. 持久化用户配置的模型到 config.yaml
            if let provider = self.model.selectedBuiltInProvider,
               !provider.isEmpty,
               let modelId = self.model.selectedBuiltInModelId,
               !modelId.isEmpty {
                DMLogger.log(
                    "completeOnboarding: 写入 model 块 provider=\(provider) model=\(modelId)",
                    name: "OnboardingViewModel"
                )
                HermesConfigWriter.shared.writeModelConfig(
                    provider: provider,
                    model: modelId,
                    baseUrl: nil
                )
            } else if self.model.modelProviderType == "custom",
                      let customId = self.model.customModelId,
                      !customId.isEmpty {
                DMLogger.log(
                    "completeOnboarding: 写入自定义 model customId=\(customId) " +
                    "url=\(self.model.customModelUrl ?? "")",
                    name: "OnboardingViewModel"
                )
                HermesConfigWriter.shared.writeModelConfig(
                    provider: "custom",
                    model: customId,
                    baseUrl: self.model.customModelUrl
                )
            } else {
                DMLogger.log(
                    "completeOnboarding: 引导中未配置具体模型，跳过写入 model 块",
                    name: "OnboardingViewModel"
                )
            }

            // 3. 写入 API Key 到 .env
            if let apiKey = self.model.apiKey, !apiKey.isEmpty {
                let provider = self.model.selectedBuiltInProvider
                    ?? (self.model.modelProviderType == "custom"
                            ? "custom"
                            : "openai")
                DMLogger.log(
                    "completeOnboarding: 写入 API Key 到 .env, provider=\(provider)",
                    name: "OnboardingViewModel"
                )
                HermesConfigWriter.shared.writeApiKeyToEnv(
                    provider: provider,
                    apiKey: apiKey
                )
            }

            // 4. 写入 agent 块（首次时）— 复用 ModelConfigViewModel 的逻辑
            // 这里直接内联实现以保持 OnboardingViewModel 独立
            self.writeAgentConfigIfNeeded()

            // 5. 重启 Gateway
            // 同步等待以确保 onboarding 完成时 gateway 已经用上新配置
            let gateway = HermesGatewayService.shared
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await gateway.stopGateway()
                _ = await gateway.startGateway()
                semaphore.signal()
            }
            semaphore.wait()
            DMLogger.log("completeOnboarding: Gateway 已重启", name: "OnboardingViewModel")

            // 6. 标记 onboarding_completed
            UserDefaults.standard.set(true, forKey: "onboarding_completed")
            DMLogger.log("已标记 onboarding_completed = true", name: "OnboardingViewModel")

            DispatchQueue.main.async {
                self.model.isCompleted = true
                self.model.isSaving = false
                DMLogger.log("completeOnboarding 完成，全部配置完毕", name: "OnboardingViewModel")
            }
        }
    }

    /// 写入 desktop pet agent 块（首次时），与 ModelConfigViewModel 中的实现对齐。
    private func writeAgentConfigIfNeeded() {
        let configPath = resolveHermesHome() + "/config.yaml"
        let content: String
        do {
            content = try String(contentsOfFile: configPath, encoding: .utf8)
        } catch {
            DMLogger.log(
                "writeAgentConfigIfNeeded: config.yaml 不存在或读取失败: \(error.localizedDescription)",
                name: "OnboardingViewModel"
            )
            return
        }

        if content.range(of: "^agent:\\s*$", options: .regularExpression) != nil {
            DMLogger.log(
                "writeAgentConfigIfNeeded: agent 块已存在，跳过",
                name: "OnboardingViewModel"
            )
            return
        }

        var block = "agent:\n"
        block += "  max_turns: 60\n"
        block += "  gateway_timeout: 1800\n"
        block += "  restart_drain_timeout: 180\n"
        block += "  api_max_retries: 3\n"
        block += "  service_tier: ''\n"
        block += "  tool_use_enforcement: auto\n"
        block += "  task_completion_guidance: true\n"
        block += "  environment_probe: true\n"
        block += "  environment_hint: ''\n"
        block += "  coding_context: auto\n"
        block += "  gateway_timeout_warning: 900\n"
        block += "  clarify_timeout: 600\n"
        block += "  gateway_notify_interval: 180\n"
        block += "  gateway_auto_continue_freshness: 3600\n"
        block += "  image_input_mode: auto\n"
        block += "  disabled_toolsets: []\n"
        block += "  verbose: false\n"
        block += "  reasoning_effort: medium\n"
        block += "  personalities:\n"
        for (key, value) in kDesktopPetPersonalities {
            let escaped = value.replacingOccurrences(of: "'", with: "''")
            block += "    \(key): '\(escaped)'\n"
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let newContent = (trimmed.isEmpty ? "" : trimmed + "\n\n") + block
        do {
            try newContent.write(toFile: configPath, atomically: true, encoding: .utf8)
            DMLogger.log(
                "writeAgentConfigIfNeeded: 写入 agent 块（\(kDesktopPetPersonalities.count) 个性格）",
                name: "OnboardingViewModel"
            )
        } catch {
            DMLogger.error(
                "writeAgentConfigIfNeeded: 写入失败: \(error.localizedDescription)",
                name: "OnboardingViewModel"
            )
        }
    }

    /// 保存桌面配置到 desktop.json（对齐 Flutter 的 _saveDesktopConfig）。
    ///
    /// 加载已有配置并保留 githubMirror 等字段，防止覆盖已配置的镜像设置。
    private func saveDesktopConfig() {
        let homeDir = NSHomeDirectory()
        let configDir = "\(homeDir)/.hermes"

        // 确保 .hermes 目录存在
        try? FileManager.default.createDirectory(
            atPath: configDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let configPath = "\(configDir)/desktop.json"

        // 加载已有配置以保留 githubMirror 等字段
        var existingConfig: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            existingConfig = json
            DMLogger.log("已加载已有配置: \(existingConfig.keys)", name: "OnboardingViewModel")
        }

        // 计算 hasUserConfiguredModel：对齐 Flutter 逻辑
        let existingUserConfigured = existingConfig["hasUserConfiguredModel"] as? Bool ?? false
        let userConfigured = existingUserConfigured ||
            model.isWelcomeStepValid ||
            (model.hermesHasModelConfigured && model.hermesHasApiKey)

        DMLogger.log("[saveDesktopConfig] hasUserConfiguredModel=\(userConfigured) (existing=\(existingUserConfigured), isWelcomeStepValid=\(model.isWelcomeStepValid), hermesHasModelConfigured=\(model.hermesHasModelConfigured), hermesHasApiKey=\(model.hermesHasApiKey))", name: "OnboardingViewModel")

        // 保留已有的 githubMirror
        let existingMirror = existingConfig["githubMirror"] as? String

        let config: [String: Any] = [
            "petPersonalityFile": model.petPersonalityFile ?? "",
            "modelProviderType": model.modelProviderType,
            "selectedBuiltInProvider": model.selectedBuiltInProvider ?? "",
            "customModelId": model.customModelId ?? "",
            "customModelUrl": model.customModelUrl ?? "",
            "customProviderName": model.customProviderName ?? "",
            "selectedBuiltInModelId": model.selectedBuiltInModelId ?? "",
            "githubMirror": existingMirror ?? model.mirrorUrl ?? "",
            "hasUserConfiguredModel": userConfigured,
        ]

        if let jsonData = try? JSONSerialization.data(
            withJSONObject: config,
            options: .prettyPrinted
        ) {
            try? jsonData.write(to: URL(fileURLWithPath: configPath))
            DMLogger.log("已保存配置到 desktop.json", name: "OnboardingViewModel")
        } else {
            DMLogger.error("保存 desktop.json 失败", name: "OnboardingViewModel")
        }
    }

    /// 重置 onboarding 状态。
    func reset() {
        let providers = model.builtInProviders
        model = OnboardingModel(
            steps: [
                OnboardingStep(index: 0, label: ""),
                OnboardingStep(index: 1, label: ""),
                OnboardingStep(index: 2, label: ""),
            ],
            aiModelOptions: [
                AiModelOption(id: "auto", name: ""),
                AiModelOption(id: "custom", name: "")
            ],
            builtInProviders: providers
        )
        DMLogger.log("onboarding 状态已重置", name: "OnboardingViewModel")
    }
}

// MARK: - Helper Types

struct CheckResult {
    let id: String
    let passed: Bool
    let detail: String?
    var error: String? = nil
}

struct HermesInstallStatus {
    let installed: Bool
    let configured: Bool
    let hasApiKey: Bool
    let hasModelConfigured: Bool
    let hermesHome: String?
}
