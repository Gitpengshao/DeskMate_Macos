import AppKit
import SwiftUI

/// 独立的桌宠悬浮窗口控制器 — 使用 NSPanel 实现，不参与主窗口生命周期。
/// 完全独立于 SwiftUI WindowGroup，避免窗口复用带来的 bug。
final class PetWindowController: NSObject {
    private var panel: NSPanel?
    private let viewModel: PetViewModel
    var onDoubleClick: (() -> Void)?

    init(viewModel: PetViewModel) {
        self.viewModel = viewModel
        super.init()
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
            .frame(width: petSize.width, height: petSize.height)
            .background(Color.clear)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: petSize.width, height: petSize.height)

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
        viewModel.resetDragState()
        panel?.orderOut(nil)
    }

    func showPet() {
        viewModel.resetDragState()
        panel?.makeKeyAndOrderFront(nil)
        // 延迟重置，覆盖拖拽状态的时序问题
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.viewModel.resetDragState()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.viewModel.resetDragState()
        }
    }

    func stopAllTimers() {
        viewModel.stopAllTimers()
    }

    // MARK: - Actions

    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        onDoubleClick?()
    }
}