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
    let viewModel = PetViewModel()
    let onboardingVM = OnboardingViewModel()

    private var petWindowController: PetWindowController?
    private let notchManager = DynamicNotchManager.shared
    private var onboardingWindow: NSWindow?
    private var mainWindow: NSWindow?
    /// 预构造的 `NSHostingController<MainPage>`，仅持有 rootView，未触发 body 求值。
    /// 真正构造 NSWindow / 访问 view 会推迟到 `continueOpenMainConsole` 中执行。
    private var preloadedHostingController: NSHostingController<MainPage>?
    private var gatewayStarted: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] applicationDidFinishLaunching: 启动")

        // 隐藏 Dock 图标，仅通过灵动岛和桌宠交互
        NSApplication.shared.setActivationPolicy(.accessory)

        DispatchQueue.main.async {
            // 1. 隐藏 WindowGroup 的占位窗口
            self.hidePlaceholderWindow()

            // 2. 创建独立的桌宠悬浮窗口
            self.setupPetWindow()

            // 3. 设置灵动岛回调
            self.notchManager.onOpenConsole = { [weak self] in
                self?.openConsole()
            }

            // 4. 启动时显示灵动岛
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.notchManager.show()
            }

            // 5. 如果 onboarding 已完成，提前启动 Hermes Gateway
            let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
            NSLog("[AppDelegate] onboarding_completed = \(onboardingCompleted)")
            if onboardingCompleted {
                // 在后台线程启动 Gateway，避免主线程阻塞导致桌宠动画卡顿
                Task.detached(priority: .userInitiated) { [weak self] in
                    await self?.startHermesGatewayIfNeeded()
                }
                // 6. 静默预加载主控制台窗口，避免点击灵动岛后卡顿
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.preloadMainWindow()
                }
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

    private func openConsole() {
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

    /// 静默预加载主控制台视图 — 仅预构造 `NSHostingController<MainPage>` 并缓存。
    ///
    /// **重要：不要在这里创建 NSWindow**。`NSWindow(contentViewController:)` 会访问
    /// `controller.view`，触发 SwiftUI body 求值；body 求值会通过 `@StateObject`
    /// 调用 `MainViewModel.init()`，其中 `self.model = MainModel(...)` 触发
    /// `@Published.willSet` → `objectWillChange.send()`，而此时正处于 view update
    /// 阶段，于是 SwiftUI 报"Modifying state during view update" 警告，并卡一帧。
    ///
    /// 正确做法：只构造 `NSHostingController`（其内部仅持有 rootView，不触发 body
    /// 求值），把 NSWindow 构造推迟到 `continueOpenMainConsole` 中（用户点击灵动岛
    /// 时），此时已有用户交互预期，可接受一帧 body 求值延迟。
    private func preloadMainWindow() {
        guard preloadedHostingController == nil, mainWindow == nil else { return }
        NSLog("[AppDelegate] preloadMainWindow: 静默预构造 hosting controller（不触发 body 求值）")

        Task.detached(priority: .userInitiated) { [weak self] in
            // 在主线程上构造 hosting controller（MainViewModel 是 @MainActor）
            let controller = await MainActor.run {
                NSHostingController(rootView: MainPage())
            }
            await MainActor.run { [weak self] in
                self?.preloadedHostingController = controller
            }
        }
    }

    private func openMainConsole() {
        NSLog("[AppDelegate] openMainConsole: 打开主控制台")

        // 异步环境检查，避免主线程文件 I/O 阻塞影响桌宠动画
        Task { [weak self] in
            guard let self = self else { return }
            let envReady = await self.isHermesEnvironmentReady()
            await MainActor.run {
                self.continueOpenMainConsole(envReady: envReady)
            }
        }
    }

    /// `openMainConsole` 的主线程续接 — 环境检查通过后展示主控制台窗口。
    private func continueOpenMainConsole(envReady: Bool) {
        // 环境缺失守卫：Python/Hermes venv 不存在则重置 onboarding 标志并跳转 OnboardingView
        guard envReady else {
            NSLog("[AppDelegate] Hermes 环境缺失，重定向到 Onboarding")
            UserDefaults.standard.set(false, forKey: "onboarding_completed")
            mainWindow?.close()
            mainWindow = nil
            openConsole()
            return
        }

        hidePetWindow()

        if let existing = mainWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            // 通知灵动岛：控制台已就绪，清除 loading 并收起
            notchManager.consoleDidOpen()
            NSLog("[AppDelegate] openMainConsole: 启动 Gateway")
            // 在后台线程启动 Gateway，避免主线程阻塞
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.startHermesGatewayIfNeeded()
            }
            startGatewayMonitoring()
            return
        }

        // 兜底：未预加载时即时创建（此时灵动岛已展示 loading）
        // 优先复用预构造的 NSHostingController（preload 阶段未触发 body 求值）
        let hostingController: NSHostingController<MainPage>
        if let preloaded = preloadedHostingController {
            hostingController = preloaded
            preloadedHostingController = nil
        } else {
            hostingController = NSHostingController(rootView: MainPage())
        }

        let window = NSWindow(contentViewController: hostingController)
        window.title = "DeskMate"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 800, height: 550)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        mainWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // 通知灵动岛：控制台已就绪，清除 loading 并收起
        notchManager.consoleDidOpen()

        NSLog("[AppDelegate] openMainConsole: 启动 Gateway")
        // 在后台线程启动 Gateway，避免主线程阻塞
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.startHermesGatewayIfNeeded()
        }
        startGatewayMonitoring()
    }

    /// 启动 Gateway 连接状态周期探测并立即刷新一次。
    private func startGatewayMonitoring() {
        GatewayConnectionManager.shared.startMonitoring()
        Task { await GatewayConnectionManager.shared.refresh() }
    }

    /// 异步检测 Hermes 运行环境是否就绪（Python venv 是否存在）。
    /// 镜像 HermesGatewayService.startGateway 的早退判断。
    /// 在后台线程执行文件 I/O，避免主线程卡顿影响桌宠动画。
    private func isHermesEnvironmentReady() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let hermesHome = AppConstants.resolveHermesHome()
            let pythonPath = "\(hermesHome)/\(AppConstants.hermesAgentDir)/\(AppConstants.hermesVenvDir)/bin/python"
            return FileManager.default.fileExists(atPath: pythonPath)
        }.value
    }

    // MARK: - Hermes Gateway

    private func startHermesGatewayIfNeeded() {
        NSLog("[AppDelegate] startHermesGatewayIfNeeded: gatewayStarted=\(gatewayStarted)")
        guard !gatewayStarted else { return }
        gatewayStarted = true

        Task.detached(priority: .userInitiated) {
            let started = await HermesGatewayService.shared.startGateway()
            // 异步环境检查，避免在 MainActor 上做文件 I/O 阻塞
            let envReady = await self.isHermesEnvironmentReady()
            await MainActor.run {
                if started {
                    NSLog("[AppDelegate] Hermes Gateway 启动成功")
                    Task { await GatewayConnectionManager.shared.refresh() }
                } else {
                    NSLog("[AppDelegate] Hermes Gateway 启动失败")
                    self.gatewayStarted = false
                    // 环境缺失时重置 onboarding 标志，下次打开控制台会跳转 OnboardingView
                    if !envReady {
                        NSLog("[AppDelegate] Hermes 环境缺失，重置 onboarding_completed")
                        UserDefaults.standard.set(false, forKey: "onboarding_completed")
                    }
                }
            }
        }
    }

    // MARK: - 宠物窗口 显示/隐藏

    private func closeOnboardingAndShowPet() {
        onboardingWindow?.close()
        onboardingWindow = nil
        showPetWindow()
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