import SwiftUI
import AppKit

/// 工作区浏览器窗口管理器 — 负责创建 / 复用独立窗口。
enum WorkspaceExplorerWindowManager {
    private static var windowControllers: [String: NSWindowController] = [:]

    /// 打开（或切换到）指定工作区的浏览器窗口。
    static func open(workingDirectory: String) {
        let key = (workingDirectory as NSString).standardizingPath

        // 如果窗口已存在，前置即可
        if let existing = windowControllers[key], let win = existing.window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = WorkspaceExplorerView(workingDirectory: key)
        let hostingCtrl = NSHostingController(rootView: view)

        let win = NSWindow(contentViewController: hostingCtrl)
        win.title = (key as NSString).lastPathComponent + " — 工作区"
        win.setContentSize(NSSize(width: 1100, height: 700))
        win.minSize = NSSize(width: 600, height: 400)
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.isReleasedWhenClosed = false
        win.delegate = WindowDelegate(onClose: {
            windowControllers.removeValue(forKey: key)
        })

        let winCtrl = NSWindowController(window: win)
        windowControllers[key] = winCtrl
        winCtrl.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - WindowDelegate

private final class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}