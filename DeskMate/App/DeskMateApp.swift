import SwiftUI
import AppKit

@main
struct DeskMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // WindowGroup 仅作为占位 — 宠物窗口由 PetWindowController 独立管理，
        // 主控制台/Onboarding 由 AppDelegate 以独立 NSWindow 管理。
        WindowGroup {
            // 正常模式：极小的隐藏窗口，宠物和主控制台由 AppDelegate 管理
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    let viewModel = PetViewModel()
    let onboardingVM = OnboardingViewModel()

    private var petWindowController: PetWindowController?
    private let notchManager = DynamicNotchManager.shared
    private(set) var onboardingWindow: NSWindow?
    private(set) var mainWindow: NSWindow?
    private var gatewayStarted: Bool = false
    /// Onboarding 期间临时保存灵动岛 "打开控制台" 回调，用于恢复。
    private var originalOnOpenConsole: (() -> Void)?
    /// 标记启动时的 Hermes 完整检测是否已完成，避免 MainPage.onAppear 与启动流程重复检测。
    private var initialHermesCheckCompleted = false
    /// 缓存 Hermes 环境检测结果，避免短时间内重复执行慢速检测。
    private var lastHermesCheckResult: Bool?
    private var lastHermesCheckTime: Date?
    private let hermesCheckCacheInterval: TimeInterval = 5.0
    /// 本次运行中强制展示 Onboarding（不持久化修改 onboarding_completed），用于 Gateway 启动失败等临时异常。
    private var forceShowOnboarding = false

    /// 程序内部重启时跳过退出确认框。
    nonisolated(unsafe) static var shouldSkipQuitConfirmation = false

    /// 退出行为偏好键。
    private enum QuitPreferences {
        static let suppressPromptKey = "quit_prompt_suppressed"
        static let killByDefaultKey = "quit_kill_gateways_default"
    }

    /// 主控制台或 Onboarding 窗口是否处于打开状态。
    var isConsoleOpen: Bool {
        mainWindow != nil || onboardingWindow != nil
    }

    /// 桌宠悬浮窗口当前是否可见。
    var isPetVisible: Bool {
        petWindowController?.isVisible ?? false
    }

    /// 桌宠 ViewModel，供语音快捷键等外部模块驱动动画。
    var petViewModel: PetViewModel? { viewModel }

    /// 更新灵动岛对“控制台是否为当前 keyWindow”的认知。
    /// 桌宠是 nonactivatingPanel，不会成为 keyWindow；当用户点击桌宠后，
    /// keyWindow 会 resign，此时灵动岛应切回“进入控制台”。
    @objc private func updateConsoleKeyState() {
        let isKey = mainWindow?.isKeyWindow == true || onboardingWindow?.isKeyWindow == true
        NSLog("[AppDelegate] updateConsoleKeyState: mainWindow.isKeyWindow=\(mainWindow?.isKeyWindow ?? false), onboardingWindow.isKeyWindow=\(onboardingWindow?.isKeyWindow ?? false), isConsoleKeyWindow=\(isKey)")
        notchManager.isConsoleKeyWindow = isKey
    }

    /// 应用变为 active 后，确保已显示的控制台窗口成为 keyWindow，
    /// 否则从 accessory 切到 regular 时 makeKeyAndOrderFront 不会立即生效。
    @objc private func handleAppDidBecomeActive() {
        NSLog("[AppDelegate] handleAppDidBecomeActive")
        if let window = mainWindow, window.isVisible, !window.isKeyWindow, window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        }
        if let window = onboardingWindow, window.isVisible, !window.isKeyWindow, window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
        }
        updateConsoleKeyState()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 单实例锁：若已有其他 DeskMate 实例在运行，激活它并终止当前进程。
        let bundleID = Bundle.main.bundleIdentifier ?? "com.deskmate.DeskMate"
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        if let existing = others.first {
            NSLog("[AppDelegate] 检测到已有实例运行（pid=\(existing.processIdentifier)），激活现有窗口并退出")
            existing.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        let launchStart = Date()
        NSLog("[AppDelegate] applicationDidFinishLaunching: 启动")

        // 隐藏 Dock 图标，仅通过灵动岛和桌宠交互
        NSApplication.shared.setActivationPolicy(.accessory)

        DispatchQueue.main.async {
            let stepStart = Date()
            // 1. 隐藏 WindowGroup 的占位窗口
            self.hidePlaceholderWindow()
            NSLog("[AppDelegate] 启动步骤 1/8 hidePlaceholderWindow 完成，耗时 %.3fs，主线程=%@",
                  Date().timeIntervalSince(stepStart), Thread.isMainThread ? "YES" : "NO")

            let step2Start = Date()
            // 2. 创建独立的桌宠悬浮窗口
            self.setupPetWindow()
            NSLog("[AppDelegate] 启动步骤 2/8 setupPetWindow 完成，耗时 %.3fs，主线程=%@",
                  Date().timeIntervalSince(step2Start), Thread.isMainThread ? "YES" : "NO")

            let step3Start = Date()
            // 3. 初始化全局语音快捷键监听（根据设置自动注册/注销）
            _ = GlobalShortcutManager.shared
            NSLog("[AppDelegate] 启动步骤 3/8 GlobalShortcutManager 完成，耗时 %.3fs，主线程=%@",
                  Date().timeIntervalSince(step3Start), Thread.isMainThread ? "YES" : "NO")

            let step4Start = Date()
            // 4. 预初始化会在主窗口 body 中作为 @ObservedObject 使用的全局共享 ViewModel，
            //    提前完成 init 与首次 objectWillChange，避免在视图更新期间触发状态修改警告。
            _ = AiChatViewModel.shared
            _ = SettingsManager.shared
            NSLog("[AppDelegate] 启动步骤 4/8 预初始化 ViewModels 完成，耗时 %.3fs，主线程=%@",
                  Date().timeIntervalSince(step4Start), Thread.isMainThread ? "YES" : "NO")

            let step5Start = Date()
            // 5. 设置灵动岛回调
            self.notchManager.onOpenConsole = { [weak self] in
                self?.openConsole()
            }
            NSLog("[AppDelegate] 启动步骤 5/8 设置灵动岛回调 完成，耗时 %.3fs，主线程=%@",
                  Date().timeIntervalSince(step5Start), Thread.isMainThread ? "YES" : "NO")

            let step6Start = Date()
            // 6. 监听控制台窗口 key 状态变化，驱动灵动岛悬浮内容在“进入控制台”与“Token 统计”之间切换。
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.updateConsoleKeyState),
                name: NSWindow.didBecomeKeyNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.updateConsoleKeyState),
                name: NSWindow.didResignKeyNotification,
                object: nil
            )
            // 应用从 accessory 切到 regular 后 activate 是异步的，窗口在 didBecomeActive 后才可能成为 keyWindow。
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.handleAppDidBecomeActive),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            self.updateConsoleKeyState()
            NSLog("[AppDelegate] 启动步骤 6/8 添加窗口观察者 完成，耗时 %.3fs，主线程=%@",
                  Date().timeIntervalSince(step6Start), Thread.isMainThread ? "YES" : "NO")

            let step7Start = Date()
            // 7. 启动时显示灵动岛
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                let showStart = Date()
                NSLog("[AppDelegate] 启动步骤 7/8 开始显示灵动岛，主线程=%@",
                      Thread.isMainThread ? "YES" : "NO")
                self?.notchManager.show()
                NSLog("[AppDelegate] 启动步骤 7/8 显示灵动岛调用返回，耗时 %.3fs，主线程=%@",
                      Date().timeIntervalSince(showStart), Thread.isMainThread ? "YES" : "NO")
            }
            NSLog("[AppDelegate] 启动步骤 7/8 已调度灵动岛显示，耗时 %.3fs，主线程=%@",
                  Date().timeIntervalSince(step7Start), Thread.isMainThread ? "YES" : "NO")

            // 8. 如果 onboarding 已完成，先完整检测 Hermes 环境再决定是否进入首页
            let step8Start = Date()
            let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
            NSLog("[AppDelegate] onboarding_completed = \(onboardingCompleted)")
            if onboardingCompleted {
                Task.detached(priority: .userInitiated) { [weak self] in
                    let envStart = Date()
                    NSLog("[AppDelegate] 启动步骤 8/8 开始检测 Hermes 环境，主线程=%@",
                          Thread.isMainThread ? "YES" : "NO")
                    let ready = await self?.isHermesEnvironmentReady() ?? false
                    NSLog("[AppDelegate] 启动步骤 8/8 Hermes 环境检测完成 ready=\(ready)，耗时 %.3fs，主线程=%@",
                          Date().timeIntervalSince(envStart), Thread.isMainThread ? "YES" : "NO")

                    if ready {
                        NSLog("[AppDelegate] Hermes 环境完整，后台启动 Gateway")
                        // 在后台线程启动 Gateway 与 Dashboard，避免主线程阻塞导致桌宠动画卡顿。
                        // 不预加载主窗口，避免 MainPage body 在 Gateway 未就绪时提前求值，
                        // 触发 @StateObject init 与 objectWillChange 导致状态更新冲突。
                        let gatewayStart = Date()
                        await HermesGatewayService.shared.stopAllGateways()
                        let gatewayReady = await self?.startAndWaitForHermesGateway() ?? false
                        NSLog("[AppDelegate] 启动步骤 8/8 Gateway 启动流程完成 ready=\(gatewayReady)，耗时 %.3fs，主线程=%@",
                              Date().timeIntervalSince(gatewayStart), Thread.isMainThread ? "YES" : "NO")

                        // Gateway 启动完成后，异步启动 Dashboard（技能管理等页面依赖它）。
                        if gatewayReady {
                            let dashboardStart = Date()
                            _ = await HermesDashboardService.shared.startDashboard()
                            NSLog("[AppDelegate] 启动步骤 8/8 Dashboard 启动流程完成，耗时 %.3fs，主线程=%@",
                                  Date().timeIntervalSince(dashboardStart), Thread.isMainThread ? "YES" : "NO")
                        }
                    } else {
                        await MainActor.run {
                            NSLog("[AppDelegate] onboarding_completed=true 但 Hermes 环境缺失，打开 Onboarding（不重置完成标志）")
                            self?.forceShowOnboarding = true
                            self?.openConsole()
                        }
                    }

                    await MainActor.run {
                        self?.initialHermesCheckCompleted = true
                    }
                }
            } else {
                self.initialHermesCheckCompleted = true
            }
            NSLog("[AppDelegate] 启动步骤 8/8 已调度 Hermes 环境检测，耗时 %.3fs，主线程=%@",
                  Date().timeIntervalSince(step8Start), Thread.isMainThread ? "YES" : "NO")
        }
    }

    // MARK: - 隐藏占位窗口

    private func hidePlaceholderWindow() {
        // 隐藏 WindowGroup 创建的所有窗口
        for window in NSApplication.shared.windows {
            window.orderOut(nil)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.level = .init(Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        }
    }

    // MARK: - 宠物窗口（独立 NSPanel）

    private func setupPetWindow() {
        let controller = PetWindowController(viewModel: viewModel)
        controller.onDoubleClick = { [weak self] in
            guard let self = self else { return }
            self.viewModel.wakeUp()
            self.notchManager.show()
        }
        controller.show()
        petWindowController = controller
    }

    // MARK: - 控制台 / Onboarding 窗口

    func openConsole() {
        // 打开控制台时恢复 Dock 图标，方便 Cmd+Tab 切换
        NSApplication.shared.setActivationPolicy(.regular)

        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
        if onboardingCompleted && !forceShowOnboarding {
            openMainConsole()
            return
        }
        forceShowOnboarding = false

        // Onboarding 窗口（已存在则提到前面）
        if let existingWindow = onboardingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            // 通知灵动岛：窗口已就绪，清除 loading 并收起
            notchManager.consoleDidOpen()
            return
        }

        hidePetWindow()

        // Onboarding 期间禁用灵动岛点击打开控制台，避免误触导致状态混乱/卡死
        if originalOnOpenConsole == nil {
            originalOnOpenConsole = notchManager.onOpenConsole
            notchManager.onOpenConsole = nil
        }

        let vm = self.onboardingVM
        let onboardingView = OnboardingView(
            viewModel: vm,
            onComplete: { [weak self] in
                self?.closeOnboardingAndShowPet()
            }
        )

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "DeskMate - 初始化设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        onboardingWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 通知灵动岛：窗口已就绪，清除 loading 并收起
        notchManager.consoleDidOpen()
    }

    // MARK: - 主控制台窗口

    private func openMainConsole() {
        NSLog("[AppDelegate] openMainConsole: 打开主控制台")

        // 使用 Task.detached 在完全独立的后台上下文执行环境检查与 Gateway 启动，
        // 避免继承主 actor/视图更新上下文，从而消除 "Modifying state during view update"。
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let envReady = await self.isHermesEnvironmentReady()
            guard envReady else {
                await MainActor.run {
                    NSLog("[AppDelegate] openMainConsole: Hermes 环境缺失，打开 Onboarding（不重置完成标志）")
                    self.forceShowOnboarding = true
                    self.openConsole()
                }
                return
            }

            // 环境文件完整，必须等 Gateway 真启动成功才能进入首页，
            // 否则首页查询会话/模型等接口会触发卡死或异常。
            let gatewayReady = await self.startAndWaitForHermesGateway()
            await MainActor.run {
                if gatewayReady {
                    self.continueOpenMainConsole(envReady: true)
                } else {
                    NSLog("[AppDelegate] openMainConsole: Gateway 启动失败，打开 Onboarding（不重置完成标志）")
                    self.forceShowOnboarding = true
                    // 立即取消 "网关启动中" 的 15s 超时任务，避免与 Onboarding 跳转冲突。
                    self.notchManager.clearWaitingForGateway()
                    self.notchManager.isLoading = false
                    self.openConsole()
                }
            }
        }
    }

    /// `openMainConsole` 的主线程续接 — 环境与 Gateway 均已就绪，直接展示主控制台窗口。
    private func continueOpenMainConsole(envReady: Bool) {
        NSLog("[AppDelegate] continueOpenMainConsole: envReady=\(envReady)")
        // 环境缺失兜底：不重置 onboarding 标志，仅临时打开 OnboardingView
        guard envReady else {
            NSLog("[AppDelegate] continueOpenMainConsole: envReady=false，打开 Onboarding（不重置完成标志）")
            self.forceShowOnboarding = true
            mainWindow?.close()
            mainWindow = nil
            openConsole()
            return
        }

        hidePetWindow()
        NSLog("[AppDelegate] continueOpenMainConsole: 已隐藏桌宠")

        if let existing = mainWindow {
            NSLog("[AppDelegate] continueOpenMainConsole: 复用已有主窗口")
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            // 通知灵动岛：控制台已就绪，清除 loading 并收起
            notchManager.consoleDidOpen()
            return
        }

        NSLog("[AppDelegate] continueOpenMainConsole: 开始构造 NSWindow")
        let hostingController = NSHostingController(rootView: MainPage())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "DeskMate"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 800, height: 550)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        mainWindow = window

        NSLog("[AppDelegate] continueOpenMainConsole: 显示主窗口")
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 启动 Dashboard 状态监控；Dashboard 本身在后台异步拉起，不阻塞窗口展示。
        startDashboardMonitoring()
        Task.detached(priority: .userInitiated) { [weak self] in
            _ = await HermesDashboardService.shared.startDashboard()
            await DashboardConnectionManager.shared.refresh()
        }

        // 延迟通知灵动岛控制台已打开，避免与主窗口首次 body 求值/状态初始化冲突。
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NSLog("[AppDelegate] continueOpenMainConsole: 通知灵动岛控制台已打开")
            self.notchManager.consoleDidOpen()
        }
    }

    /// 启动 Gateway 连接状态周期探测并立即刷新一次。
    private func startGatewayMonitoring() {
        GatewayConnectionManager.shared.startMonitoring()
        Task { await GatewayConnectionManager.shared.refresh() }
    }

    /// 异步完整检测 Hermes 运行环境是否就绪。
    /// 对齐 Onboarding 的判定标准：已安装、已配置、API Key 已配置、默认模型已配置。
    /// 在后台线程执行，避免主线程卡顿影响桌宠动画。
    private func isHermesEnvironmentReady() async -> Bool {
        let start = Date()
        // 5 秒内结果缓存，避免启动/点击控制台/MainPage.onAppear 重复执行慢速检测。
        if let lastResult = lastHermesCheckResult,
           let lastTime = lastHermesCheckTime,
           Date().timeIntervalSince(lastTime) < hermesCheckCacheInterval {
            NSLog("[AppDelegate] isHermesEnvironmentReady: 使用缓存结果 \(lastResult)")
            return lastResult
        }

        NSLog("[AppDelegate] isHermesEnvironmentReady: 开始后台检测，主线程=%@",
              Thread.isMainThread ? "YES" : "NO")
        let ready = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return false }
            let checkStart = Date()
            let status = self.onboardingVM.checkHermes()
            let result = status.installed && status.configured && status.hasApiKey && status.hasModelConfigured
            NSLog("[AppDelegate] isHermesEnvironmentReady: installed=\(status.installed), configured=\(status.configured), hasApiKey=\(status.hasApiKey), hasModelConfigured=\(status.hasModelConfigured), ready=\(result), 检测耗时 %.3fs, 主线程=%@",
                  Date().timeIntervalSince(checkStart), Thread.isMainThread ? "YES" : "NO")
            return result
        }.value

        lastHermesCheckResult = ready
        lastHermesCheckTime = Date()
        NSLog("[AppDelegate] isHermesEnvironmentReady: 返回 ready=\(ready)，总耗时 %.3fs",
              Date().timeIntervalSince(start))
        return ready
    }

    /// 供首页兜底调用：若 Hermes 环境不完整，关闭首页并跳转到 Onboarding。
    func ensureHermesEnvironmentOrRedirect() {
        // 启动阶段已由 applicationDidFinishLaunching 完成完整检测，
        // 在标志位设置前跳过，避免与启动流程重复执行慢速检测。
        guard initialHermesCheckCompleted else {
            NSLog("[AppDelegate] 首页兜底检测：启动初始检测尚未完成，跳过")
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let ready = await self?.isHermesEnvironmentReady() ?? false
            await MainActor.run {
                if !ready {
                    NSLog("[AppDelegate] 首页兜底检测：Hermes 环境缺失，打开 Onboarding（不重置完成标志）")
                    self?.forceShowOnboarding = true
                    self?.mainWindow?.close()
                    self?.mainWindow = nil
                    self?.openConsole()
                }
            }
        }
    }

    // MARK: - Hermes Gateway

    /// 启动 Gateway 并等待其就绪；返回是否成功。幂等。
    private func startAndWaitForHermesGateway() async -> Bool {
        let start = Date()
        NSLog("[AppDelegate] startAndWaitForHermesGateway: 进入，gatewayStarted=\(gatewayStarted)，主线程=%@",
              Thread.isMainThread ? "YES" : "NO")
        // 若 Gateway 已在运行且健康，直接复用，避免 Onboarding 完成后再无意义重启
        // 导致旧实例端口未释放、新实例因 address already in use 启动失败。
        if await HermesGatewayService.shared.isHealthy() {
            NSLog("[AppDelegate] startAndWaitForHermesGateway: Gateway 已在运行且健康，直接复用")
            gatewayStarted = true
            await MainActor.run {
                // Gateway 就绪后再启动周期性健康探测，避免未就绪时反复刷新触发视图循环。
                self.startGatewayMonitoring()
                // Gateway 就绪后再通知灵动岛切换到今日汇总视图，避免未就绪时切换 content 卡死。
                self.notchManager.consoleDidOpen()
            }
            NSLog("[AppDelegate] startAndWaitForHermesGateway: 复用路径完成，总耗时 %.3fs",
                  Date().timeIntervalSince(start))
            return true
        }

        guard !gatewayStarted else {
            let ready = HermesGatewayService.shared.isReady
            NSLog("[AppDelegate] startAndWaitForHermesGateway: gatewayStarted=true, isReady=\(ready)")
            return ready
        }
        gatewayStarted = true

        let gatewayStart = Date()
        let started = await HermesGatewayService.shared.startGateway()
        NSLog("[AppDelegate] startAndWaitForHermesGateway: startGateway 返回 started=\(started)，耗时 %.3fs",
              Date().timeIntervalSince(gatewayStart))
        if started {
            NSLog("[AppDelegate] startAndWaitForHermesGateway: Gateway 启动成功")
            await MainActor.run {
                // Gateway 就绪后再启动周期性健康探测，避免未就绪时反复刷新触发视图循环。
                self.startGatewayMonitoring()
                // Gateway 就绪后再通知灵动岛切换到今日汇总视图，避免未就绪时切换 content 卡死。
                self.notchManager.consoleDidOpen()
            }
        } else {
            NSLog("[AppDelegate] startAndWaitForHermesGateway: Gateway 启动失败")
            gatewayStarted = false
        }
        NSLog("[AppDelegate] startAndWaitForHermesGateway: 总耗时 %.3fs，返回 started=\(started)",
              Date().timeIntervalSince(start))
        return started
    }

    /// 在后台启动 Gateway（应用启动阶段使用，不阻塞调用方）。
    private func startHermesGatewayIfNeeded() {
        NSLog("[AppDelegate] startHermesGatewayIfNeeded: gatewayStarted=\(gatewayStarted)，主线程=%@",
              Thread.isMainThread ? "YES" : "NO")
        guard !gatewayStarted else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let start = Date()
            NSLog("[AppDelegate] startHermesGatewayIfNeeded Task: 开始启动 Gateway，主线程=%@",
                  Thread.isMainThread ? "YES" : "NO")
            _ = await self?.startAndWaitForHermesGateway()
            NSLog("[AppDelegate] startHermesGatewayIfNeeded Task: Gateway 启动流程结束，耗时 %.3fs，主线程=%@",
                  Date().timeIntervalSince(start), Thread.isMainThread ? "YES" : "NO")
        }
    }

    // MARK: - Hermes Dashboard

    /// 在后台启动 Dashboard（应用启动/主控制台打开时使用，不阻塞调用方）。
    private func startHermesDashboardIfNeeded() {
        NSLog("[AppDelegate] startHermesDashboardIfNeeded: 主线程=%@",
              Thread.isMainThread ? "YES" : "NO")
        Task.detached(priority: .userInitiated) {
            let start = Date()
            NSLog("[AppDelegate] startHermesDashboardIfNeeded Task: 开始启动 Dashboard，主线程=%@",
                  Thread.isMainThread ? "YES" : "NO")
            _ = await HermesDashboardService.shared.startDashboard()
            NSLog("[AppDelegate] startHermesDashboardIfNeeded Task: Dashboard 启动流程结束，耗时 %.3fs，主线程=%@",
                  Date().timeIntervalSince(start), Thread.isMainThread ? "YES" : "NO")
        }
    }

    /// 启动 Dashboard 健康状态周期探测。
    private func startDashboardMonitoring() {
        DashboardConnectionManager.shared.startMonitoring()
        Task { await DashboardConnectionManager.shared.refresh() }
    }

    // MARK: - 宠物窗口 显示/隐藏

    private func closeOnboardingAndShowPet() {
        onboardingWindow?.close()
        onboardingWindow = nil
        showPetWindow()
        restoreOnOpenConsole()
    }

    /// 恢复灵动岛 "打开控制台" 回调。
    private func restoreOnOpenConsole() {
        if let original = originalOnOpenConsole {
            notchManager.onOpenConsole = original
            originalOnOpenConsole = nil
        }
    }

    private func hidePetWindow() {
        petWindowController?.hide()
    }

    private func showPetWindow() {
        petWindowController?.showPet()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NSLog("[AppDelegate] applicationShouldTerminate: 收到退出请求")

        // 1. 程序内部重启：跳过确认框，但仍默认停止 Gateway，确保新实例启动时端口已释放。
        if Self.shouldSkipQuitConfirmation {
            Self.shouldSkipQuitConfirmation = false
            NSLog("[AppDelegate] applicationShouldTerminate: 程序内部重启，跳过确认框并停止 Gateway")
            return startQuitCleanup(killGateways: true)
        }

        // 2. 用户已选择“记住选择”，直接按偏好执行。
        let suppressed = UserDefaults.standard.bool(forKey: QuitPreferences.suppressPromptKey)
        if suppressed {
            let killByDefault = UserDefaults.standard.bool(forKey: QuitPreferences.killByDefaultKey)
            NSLog("[AppDelegate] applicationShouldTerminate: 已记忆偏好 killGateways=\(killByDefault)")
            return startQuitCleanup(killGateways: killByDefault)
        }

        // 3. 弹出确认框（terminateLater 会暂停退出流程，等 alert 结束后再 reply）。
        DispatchQueue.main.async { [weak self] in
            self?.presentQuitAlert()
        }
        return .terminateLater
    }

    /// 显示退出确认框，左下角带“以后默认此选项”勾选框。
    private func presentQuitAlert() {
        let alert = NSAlert()
        alert.messageText = "退出 DeskMate"
        alert.informativeText = "是否同时停止所有 Hermes Gateway 进程？"
        alert.addButton(withTitle: "停止并退出")
        alert.addButton(withTitle: "仅退出应用")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "以后默认此选项"

        let response = alert.runModal()
        let killGateways = (response == .alertFirstButtonReturn)
        let remember = (alert.suppressionButton?.state == .on)

        NSLog("[AppDelegate] presentQuitAlert: 选择=\(killGateways ? "停止并退出" : "仅退出应用"), 记住=\(remember)")

        if remember {
            UserDefaults.standard.set(true, forKey: QuitPreferences.suppressPromptKey)
            UserDefaults.standard.set(killGateways, forKey: QuitPreferences.killByDefaultKey)
        }

        _ = startQuitCleanup(killGateways: killGateways)
    }

    /// 执行退出清理并回复系统是否允许退出。
    private func startQuitCleanup(killGateways: Bool) -> NSApplication.TerminateReply {
        NSLog("[AppDelegate] startQuitCleanup: killGateways=\(killGateways)")
        if killGateways {
            // 异步关闭 Gateway 与 Dashboard，不阻塞退出流程，确保 app 立即响应退出。
            Task.detached {
                await HermesGatewayService.shared.stopAllGateways()
                await HermesDashboardService.shared.stopDashboard()
            }
        }
        return .terminateNow
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == onboardingWindow {
            onboardingWindow = nil
            showPetWindow()
            // 控制台关闭：恢复灵动岛悬浮展开能力
            notchManager.consoleDidClose()
            restoreAccessoryPolicy()
            restoreOnOpenConsole()
        }
        if notification.object as? NSWindow == mainWindow {
            mainWindow = nil
            showPetWindow()
            // 控制台关闭：恢复灵动岛悬浮展开能力
            notchManager.consoleDidClose()
            restoreAccessoryPolicy()
            GatewayConnectionManager.shared.stopMonitoring()
            DashboardConnectionManager.shared.stopMonitoring()
        }
    }

    /// 控制台关闭后恢复隐藏 Dock 图标
    private func restoreAccessoryPolicy() {
        // 仅当所有控制台窗口都已关闭时才隐藏 Dock
        if onboardingWindow == nil && mainWindow == nil {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
