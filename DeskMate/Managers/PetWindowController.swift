import AppKit
import SwiftUI
import Combine

/// 独立的桌宠悬浮窗口控制器 — 使用 NSPanel 实现，不参与主窗口生命周期。
/// 完全独立于 SwiftUI WindowGroup，避免窗口复用带来的 bug。
final class PetWindowController: NSObject {
    private var panel: NSPanel?
    private let viewModel: PetViewModel
    private var cancellables = Set<AnyCancellable>()
    private var transparencyTimer: Timer?
    private var isHoveringTransparent = false

    var onDoubleClick: (() -> Void)?

    init(viewModel: PetViewModel) {
        self.viewModel = viewModel
        super.init()
        setupSettingsBindings()
    }

    deinit {
        transparencyTimer?.invalidate()
    }

    // MARK: - 创建 & 配置

    func show() {
        guard panel == nil else {
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        let petSize = viewModel.petSize

        // 创建独立 NSPanel — 不依赖 WindowGroup
        let contentView = PetImageView(viewModel: viewModel)
            .background(Color.clear)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: petSize.width, height: petSize.height)
        hostingView.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: petSize.width, height: petSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 透明悬浮配置
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.isOpaque = false
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        // 双击打开控制台
        let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClickGesture.numberOfClicksRequired = 2
        panel.contentView?.addGestureRecognizer(doubleClickGesture)

        // 悬浮透明：使用 TrackingArea 检测鼠标进入，再通过轮询检测离开
        //（设置 ignoresMouseEvents = true 后系统不再发送 mouseExited）
        setupHoverTracking(for: panel)

        // 居中放置
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - petSize.width / 2
            let y = screenFrame.midY - petSize.height / 2
            panel.setFrame(NSRect(x: x, y: y, width: petSize.width, height: petSize.height), display: false)
        }

        self.panel = panel

        // 显示窗口
        panel.orderFront(nil)

        // 绑定 ViewModel（设置鼠标监听、行走动画等）
        viewModel.configure(with: panel)
    }

    func hide() {
        viewModel.sleep()
        panel?.orderOut(nil)
    }

    func showPet() {
        viewModel.wakeUpAndWalk()
        panel?.makeKeyAndOrderFront(nil)
    }

    func stopAllTimers() {
        viewModel.stopAllTimers()
    }

    // MARK: - Settings Bindings

    private func setupSettingsBindings() {
        SettingsManager.shared.$isHoverTransparentEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTransparencyState()
            }
            .store(in: &cancellables)
    }

    // MARK: - Hover Transparency

    private func setupHoverTracking(for panel: NSPanel) {
        guard let contentView = panel.contentView else { return }

        let hoverView = HoverTrackingView(frame: contentView.bounds)
        hoverView.autoresizingMask = [.width, .height]
        hoverView.onMouseEntered = { [weak self] in
            guard SettingsManager.shared.isHoverTransparentEnabled else { return }
            self?.applyTransparentHoverState(true)
        }
        hoverView.onMouseExited = { [weak self] in
            self?.applyTransparentHoverState(false)
        }
        contentView.addSubview(hoverView)
    }

    private func applyTransparentHoverState(_ hovering: Bool) {
        guard let panel = panel else { return }

        if hovering {
            isHoveringTransparent = true
            panel.alphaValue = 0.05
            panel.ignoresMouseEvents = true
            // 启动轮询，补偿设置 ignoresMouseEvents 后 mouseExited 可能不被触发的情况
            startTransparencyPolling()
        } else {
            isHoveringTransparent = false
            panel.alphaValue = 1.0
            panel.ignoresMouseEvents = false
            stopTransparencyPolling()
        }
    }

    private func updateTransparencyState() {
        guard let panel = panel else { return }

        if !SettingsManager.shared.isHoverTransparentEnabled {
            applyTransparentHoverState(false)
            return
        }

        // 设置刚启用且鼠标当前就在窗口内时立即生效
        let mouseLoc = NSEvent.mouseLocation
        let isHovering = panel.frame.contains(mouseLoc)
        if isHovering && !isHoveringTransparent {
            applyTransparentHoverState(true)
        }
    }

    private func startTransparencyPolling() {
        guard transparencyTimer == nil else { return }
        transparencyTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkMouseLeftWindow()
        }
    }

    private func stopTransparencyPolling() {
        transparencyTimer?.invalidate()
        transparencyTimer = nil
    }

    private func checkMouseLeftWindow() {
        guard let panel = panel, isHoveringTransparent else { return }
        let mouseLoc = NSEvent.mouseLocation
        if !panel.frame.contains(mouseLoc) {
            applyTransparentHoverState(false)
        }
    }

    // MARK: - Actions

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        onDoubleClick?()
    }
}

// MARK: - Hover Tracking View

/// 透明叠加视图，用于向非 NSResponder 的控制器转发鼠标进入/离开事件。
private final class HoverTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
