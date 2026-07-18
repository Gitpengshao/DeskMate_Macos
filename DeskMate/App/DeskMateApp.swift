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

        NSLog("[AppDelegate] applicationDidFinishLaunching: 启动")

        // 隐藏 Dock 图标，仅通过灵动岛和桌宠交互
        NSApplication.shared.setActivationPolicy(.accessory)

        DispatchQueue.main.async {
            // 1. 隐藏 WindowGroup 的占位窗口
            self.hidePlaceholderWindow()

            // 2. 创建独立的桌宠悬浮窗口
            self.setupPetWindow()

            // 3. 初始化全局语音快捷键监听（根据设置自动注册/注销）
            _ = GlobalShortcutManager.shared

            // 4. 预初始化会在主窗口 body 中作为 @ObservedObject 使用的全局共享 ViewModel，
            //    提前完成 init 与首次 objectWillChange，避免在视图更新期间触发状态修改警告。
            _ = AiChatViewModel.shared
            _ = SettingsManager.shared

            // 5. 设置灵动岛回调
            self.notchManager.onOpenConsole = { [weak self] in
                self?.openConsole()
            }

            // 4. 启动时显示灵动岛
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.notchManager.show()
            }

            // 5. 如果 onboarding 已完成，先完整检测 Hermes 环境再决定是否进入首页
            let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
            NSLog("[AppDelegate] onboarding_completed = \(onboardingCompleted)")
            if onboardingCompleted {
                Task.detached(priority: .userInitiated) { [weak self] in
                    let ready = await self?.isHermesEnvironmentReady() ?? false
                    await MainActor.run {
                        self?.initialHermesCheckCompleted = true
                        if ready {
                            NSLog("[AppDelegate] Hermes 环境完整，后台启动 Gateway")
                            // 在后台线程启动 Gateway，避免主线程阻塞导致桌宠动画卡顿。
                            // 不预加载主窗口，避免 MainPage body 在 Gateway 未就绪时提前求值，
                            // 触发 @StateObject init 与 objectWillChange 导致状态更新冲突。
                            Task.detached(priority: .userInitiated) { [weak self] in
                                await self?.startHermesGatewayIfNeeded()
                            }
                        } else {
                            NSLog("[AppDelegate] onboarding_completed=true 但 Hermes 环境缺失，重置标志并打开 Onboarding")
                            UserDefaults.standard.set(false, forKey: "onboarding_completed")
                            self?.openConsole()
                        }
                    }
                }
            } else {
                self.initialHermesCheckCompleted = true
            }
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
        if onboardingCompleted {
            openMainConsole()
            return
        }

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
                    NSLog("[AppDelegate] openMainConsole: Hermes 环境缺失，重定向到 Onboarding")
                    UserDefaults.standard.set(false, forKey: "onboarding_completed")
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
                    NSLog("[AppDelegate] openMainConsole: Gateway 启动失败，重定向到 Onboarding")
                    UserDefaults.standard.set(false, forKey: "onboarding_completed")
                    self.notchManager.isLoading = false
                    self.openConsole()
                }
            }
        }
    }

    /// `openMainConsole` 的主线程续接 — 环境与 Gateway 均已就绪，直接展示主控制台窗口。
    private func continueOpenMainConsole(envReady: Bool) {
        NSLog("[AppDelegate] continueOpenMainConsole: envReady=\(envReady)")
        // 环境缺失兜底：重置 onboarding 标志并跳转 OnboardingView
        guard envReady else {
            NSLog("[AppDelegate] continueOpenMainConsole: envReady=false，重定向到 Onboarding")
            UserDefaults.standard.set(false, forKey: "onboarding_completed")
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
        // 5 秒内结果缓存，避免启动/点击控制台/MainPage.onAppear 重复执行慢速检测。
        if let lastResult = lastHermesCheckResult,
           let lastTime = lastHermesCheckTime,
           Date().timeIntervalSince(lastTime) < hermesCheckCacheInterval {
            NSLog("[AppDelegate] isHermesEnvironmentReady: 使用缓存结果 \(lastResult)")
            return lastResult
        }

        let ready = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return false }
            let status = self.onboardingVM.checkHermes()
            let result = status.installed && status.configured && status.hasApiKey && status.hasModelConfigured
            NSLog("[AppDelegate] isHermesEnvironmentReady: installed=\(status.installed), configured=\(status.configured), hasApiKey=\(status.hasApiKey), hasModelConfigured=\(status.hasModelConfigured), ready=\(result)")
            return result
        }.value

        lastHermesCheckResult = ready
        lastHermesCheckTime = Date()
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
                    NSLog("[AppDelegate] 首页兜底检测：Hermes 环境缺失，重定向到 Onboarding")
                    UserDefaults.standard.set(false, forKey: "onboarding_completed")
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
        guard !gatewayStarted else {
            let ready = HermesGatewayService.shared.isReady
            NSLog("[AppDelegate] startAndWaitForHermesGateway: gatewayStarted=true, isReady=\(ready)")
            return ready
        }
        gatewayStarted = true

        let started = await HermesGatewayService.shared.startGateway()
        if started {
            NSLog("[AppDelegate] startAndWaitForHermesGateway: Gateway 启动成功")
            await MainActor.run {
                // Gateway 启动成功后再启动周期性健康探测，避免未就绪时反复刷新触发视图循环。
                self.startGatewayMonitoring()
                // Gateway 就绪后再通知灵动岛切换到今日汇总视图，避免未就绪时切换 content 卡死。
                self.notchManager.consoleDidOpen()
            }
        } else {
            NSLog("[AppDelegate] startAndWaitForHermesGateway: Gateway 启动失败")
            gatewayStarted = false
        }
        return started
    }

    /// 在后台启动 Gateway（应用启动阶段使用，不阻塞调用方）。
    private func startHermesGatewayIfNeeded() {
        NSLog("[AppDelegate] startHermesGatewayIfNeeded: gatewayStarted=\(gatewayStarted)")
        guard !gatewayStarted else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            _ = await self?.startAndWaitForHermesGateway()
        }
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
        NSLog("[AppDelegate] applicationShouldTerminate: 准备停止所有 Gateway")
        Task.detached {
            await HermesGatewayService.shared.stopAllGateways()
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
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