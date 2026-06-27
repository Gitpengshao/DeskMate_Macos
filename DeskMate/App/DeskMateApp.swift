import SwiftUI
import AppKit

@main
struct DeskMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// 从启动参数 `--show-webview <URL>` 中提取 WebView 模式的目标 URL。
    /// 提取逻辑与 AppDelegate 保持一致 — AppDelegate 负责真正的窗口生命周期。
    private static let launchWebViewURL: String? = {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--show-webview"),
              idx + 1 < args.count else { return nil }
        let value = args[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }()

    var body: some Scene {
        // 单一 WindowGroup：宠物窗口 + 主控制台由 AppDelegate 单独管理。
        // WebView 模式启动时仅展示 WebView 窗口，并跳过宠物/状态栏/Gateway。
        WindowGroup {
            if Self.launchWebViewURL == nil {
                ContentView()
                    .environmentObject(appDelegate.viewModel)
            } else {
                MMWebViewWindow(urlString: Self.launchWebViewURL ?? "") {
                    NSApp.terminate(nil)
                }
                .frame(minWidth: 800, minHeight: 500)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = PetViewModel()
    let onboardingVM = OnboardingViewModel()
    private let statusBarManager = StatusBarManager()
    private var onboardingWindow: NSWindow?
    private var mainWindow: NSWindow?
    /// 标记 Gateway 是否已启动（与 Flutter app.dart 中 startGateway 调用对齐）。
    private var gatewayStarted: Bool = false

    /// WebView 模式的目标 URL — 通过启动参数 `--show-webview <URL>` 注入。
    /// 非 nil 时整个进程退化为"单窗口 WebView 浏览器"，不初始化宠物/状态栏/Gateway。
    let webViewURL: String? = {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--show-webview"),
              idx + 1 < args.count else { return nil }
        let value = args[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }()

    /// 是否运行在 WebView 模式（独立进程仅展示 Provider 页面）。
    var isWebViewMode: Bool { webViewURL != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] applicationDidFinishLaunching: 应用启动 (webViewMode=\(isWebViewMode))")
        // WebView 模式：不初始化宠物窗口、状态栏、Gateway — 只让 SwiftUI 场景里
        // 的 WindowGroup 展示 WebView 窗口，关闭后由 applicationShouldTerminateAfterLastWindowClosed 退出。
        if isWebViewMode { return }
        DispatchQueue.main.async {
            // 1. 配置宠物窗口（始终存在、透明、悬浮）
            self.configurePetWindow()

            // 2. 设置状态栏托盘
            self.statusBarManager.setup()
            self.statusBarManager.onOpenConsole = { [weak self] in
                self?.openConsole()
            }

            // 3. 如果 onboarding 已完成，提前启动 Hermes Gateway
            //    对齐 Flutter app.dart 中 startGateway 调用
            let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
            NSLog("[AppDelegate] onboarding_completed = \(onboardingCompleted)")
            if onboardingCompleted {
                self.startHermesGatewayIfNeeded()
            }
        }
    }

    // MARK: - 宠物窗口（独立进程、透明悬浮）

    private func configurePetWindow() {
        guard let window = NSApplication.shared.windows.first else { return }

        let petSize = viewModel.petSize

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.styleMask = [.borderless]
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.isOpaque = false

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - petSize.width / 2
            let y = screenFrame.midY - petSize.height / 2
            window.setFrame(
                NSRect(x: x, y: y, width: petSize.width, height: petSize.height),
                display: true
            )
        }

        viewModel.configure(with: window)
    }

    // MARK: - 控制台/Onboarding 窗口（独立窗口）

    private func openConsole() {
        let onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
        if onboardingCompleted {
            // Onboarding 已完成 → 打开主控制台窗口
            openMainConsole()
            return
        }

        // 如果 onboarding 窗口已存在，直接提到前面
        if let existingWindow = onboardingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        // 隐藏宠物
        hidePetWindow()

        // 创建 onboarding 窗口
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
    }

    // MARK: - 主控制台窗口（MainPage）

    private func openMainConsole() {
        NSLog("[AppDelegate] openMainConsole: 打开主控制台")
        // 隐藏桌面宠物
        hidePetWindow()

        // 如果主窗口已存在，直接提到前面
        if let existing = mainWindow {
            NSLog("[AppDelegate] openMainConsole: 主窗口已存在，直接显示")
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

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

        NSLog("[AppDelegate] openMainConsole: 主窗口已显示，启动 Gateway")
        // 启动 Hermes Gateway（对齐 Flutter app.dart 中 startGateway 调用）
        startHermesGatewayIfNeeded()
    }

    /// 在后台异步启动 Hermes Gateway — 对齐 Flutter app.dart 中的启动逻辑。
    ///
    /// 仅在 Gateway 尚未启动时调用。
    /// 异步执行不阻塞 UI；启动失败仅记录日志。
    private func startHermesGatewayIfNeeded() {
        NSLog("[AppDelegate] startHermesGatewayIfNeeded: 调用, gatewayStarted=\(gatewayStarted)")
        guard !gatewayStarted else {
            NSLog("[AppDelegate] startHermesGatewayIfNeeded: 已启动过，跳过")
            return
        }
        gatewayStarted = true // 防止重复启动
        NSLog("[AppDelegate] startHermesGatewayIfNeeded: 异步启动 Hermes Gateway...")

        Task.detached(priority: .userInitiated) {
            NSLog("[AppDelegate] Task.detached: 开始执行 startGateway")
            let started = await HermesGatewayService.shared.startGateway()
            NSLog("[AppDelegate] Task.detached: startGateway 返回 \(started)")
            await MainActor.run {
                if started {
                    NSLog("[AppDelegate] Hermes Gateway 启动成功")
                } else {
                    NSLog("[AppDelegate] Hermes Gateway 启动失败")
                    self.gatewayStarted = false // 允许下次重试
                }
            }
        }
        NSLog("[AppDelegate] startHermesGatewayIfNeeded: Task.detached 已派发")
    }

    private func closeOnboardingAndShowPet() {
        onboardingWindow?.close()
        onboardingWindow = nil
        showPetWindow()
    }

    private func hidePetWindow() {
        // 隐藏时立即重置拖拽状态
        viewModel.resetDragState()
        NSApplication.shared.windows.first?.orderOut(nil)
    }

    private func showPetWindow() {
        // 显示前先重置拖拽状态，确保初始动画是 run
        viewModel.resetDragState()
        NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        // 多次延迟重置，覆盖 mouseDownTimer(0.25s) 等所有可能的时序问题
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.viewModel.resetDragState()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.viewModel.resetDragState()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // WebView 模式：窗口关闭即退出进程；
        // 正常模式：保留进程（继续显示宠物/状态栏托盘）。
        isWebViewMode
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == onboardingWindow {
            onboardingWindow = nil
            showPetWindow()
        }
        if notification.object as? NSWindow == mainWindow {
            mainWindow = nil
            // 关闭主控制台时重新显示桌面宠物
            showPetWindow()
        }
    }
}
