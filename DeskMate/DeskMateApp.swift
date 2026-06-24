import SwiftUI
import AppKit

@main
struct DeskMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.viewModel)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = PetViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            self.configureWindow()
        }
    }

    private func configureWindow() {
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

        // 鼠标事件监听：按下→拖拽动画，松开→走路动画
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self = self, let window = self.viewModel.window else { return event }
            let locationInWindow = event.locationInWindow
            let contentRect = window.contentView?.bounds ?? .zero

            switch event.type {
            case .leftMouseDown:
                if contentRect.contains(locationInWindow) {
                    self.viewModel.handleMouseDown()
                }
            case .leftMouseUp:
                // mouseUp 无论在哪里都要处理（用户可能拖到窗口外再松开）
                self.viewModel.handleMouseUp()
            default:
                break
            }
            return event
        }

        viewModel.window = window
        viewModel.startWalking()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
