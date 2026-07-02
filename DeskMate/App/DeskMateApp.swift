import SwiftUI
import AppKit

@main
struct DeskMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// 从启动参数 `--show-webview <URL>` 中提取 WebView 模式的目标 URL。
    private static let launchWebViewURL: String? = {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--show-webview"),
              idx + 1 < args.count else { return nil }
        let value = args[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }()

    var body: some Scene {
        // WindowGroup 仅作为占位 — 宠物窗口由 PetWindowController 独立管理，
        // 主控制台/Onboarding 由 AppDelegate 以独立 NSWindow 管理。
        // WebView 模式启动时展示 WebView 窗口。
        WindowGroup {
            if Self.launchWebViewURL == nil {
                // 正常模式：极小的隐藏窗口，宠物和主控制台由 AppDelegate 管理
                Color.clear
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            } else {
                MMWebViewWindow(urlString: Self.launchWebViewURL ?? "") {
                    NSApp.terminate(nil)
                }
                .frame(minWidth: 800, minHeight: 500)
            }
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
    private var gatewayStarted: Bool = false

    /// WebView 模式的目标 URL
    let webViewURL: String? = {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--show-webview"),
              idx + 1 < args.count else { return nil }
        let value = args[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }()

    var isWebViewMode: Bool { webViewURL != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] applicationDidFinishLaunching: 启动 (webViewMode=\(isWebViewMode))")

        if isWebViewMode { return }

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
                self.startHermesGatewayIfNeeded()
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
            self?.notchManager.show()
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

    /// 静默预加载主控制台窗口 — 在启动后延迟创建窗口实例但不显示，
    /// 这样点击灵动岛时只需 orderFront，避免 SwiftUI 视图初始化导致的卡顿。
    private func preloadMainWindow() {
        guard mainWindow == nil else { return }
        NSLog("[AppDelegate] preloadMainWindow: 静默预加载主控制台窗口")

        let mainView = MainPage()
        let hostingController = NSHostingController(rootView: mainView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "DeskMate"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 800, height: 550)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        mainWindow = window
        // 不调用 makeKeyAndOrderFront，保持隐藏
    }

    private func openMainConsole() {
        NSLog("[AppDelegate] openMainConsole: 打开主控制台")

        // 环境缺失守卫：Python/Hermes venv 不存在则重置 onboarding 标志并跳转 OnboardingView
        guard isHermesEnvironmentReady() else {
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
            startHermesGatewayIfNeeded()
            startGatewayMonitoring()
            return
        }

        // 兜底：未预加载时即时创建（此时灵动岛已展示 loading）
        let mainView = MainPage()
        let hostingController = NSHostingController(rootView: mainView)

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
        startHermesGatewayIfNeeded()
        startGatewayMonitoring()
    }

    /// 启动 Gateway 连接状态周期探测并立即刷新一次。
    private func startGatewayMonitoring() {
        GatewayConnectionManager.shared.startMonitoring()
        Task { await GatewayConnectionManager.shared.refresh() }
    }

    /// 检测 Hermes 运行环境是否就绪（Python venv 是否存在）。
    /// 镜像 HermesGatewayService.startGateway 的早退判断。
    private func isHermesEnvironmentReady() -> Bool {
        let hermesHome = AppConstants.resolveHermesHome()
        let pythonPath = "\(hermesHome)/\(AppConstants.hermesAgentDir)/\(AppConstants.hermesVenvDir)/bin/python"
        return FileManager.default.fileExists(atPath: pythonPath)
    }

    // MARK: - Hermes Gateway

    private func startHermesGatewayIfNeeded() {
        NSLog("[AppDelegate] startHermesGatewayIfNeeded: gatewayStarted=\(gatewayStarted)")
        guard !gatewayStarted else { return }
        gatewayStarted = true

        Task.detached(priority: .userInitiated) {
            let started = await HermesGatewayService.shared.startGateway()
            await MainActor.run {
                if started {
                    NSLog("[AppDelegate] Hermes Gateway 启动成功")
                    Task { await GatewayConnectionManager.shared.refresh() }
                } else {
                    NSLog("[AppDelegate] Hermes Gateway 启动失败")
                    self.gatewayStarted = false
                    // 环境缺失时重置 onboarding 标志，下次打开控制台会跳转 OnboardingView
                    if !self.isHermesEnvironmentReady() {
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
        isWebViewMode
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