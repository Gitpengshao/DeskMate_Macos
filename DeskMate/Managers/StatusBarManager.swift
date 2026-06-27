import AppKit

final class StatusBarManager {
    private var statusItem: NSStatusItem?
    /// Callback when "进入App控制台" is clicked
    var onOpenConsole: (() -> Void)?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let trayImage = NSImage(named: "tray") {
                let size = NSSize(width: 18, height: 18)
                trayImage.size = size
                button.image = trayImage
            }
        }

        let menu = NSMenu()

        let consoleItem = NSMenuItem(
            title: "进入App控制台",
            action: #selector(openConsole),
            keyEquivalent: ""
        )
        consoleItem.target = self
        menu.addItem(consoleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出App",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openConsole() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        onOpenConsole?()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
