import AppKit
import Combine

/// 全局语音快捷键监听管理器。
///
/// 通过长按组合键触发：按下快捷键开始聆听，松开按键直接结束并发送。
/// 需要用户在「系统设置 › 隐私与安全性 › 辅助功能」中授权 DeskMate。
@MainActor
final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var monitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// 只关心 Command / Option / Control / Shift，避免 Fn/Numpad 等标志导致匹配失败。
    private let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    private init() {
        setupBindings()
    }

    private func setupBindings() {
        SettingsManager.shared.$isVoiceShortcutEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRegistration()
            }
            .store(in: &cancellables)

        SettingsManager.shared.$voiceShortcut
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRegistration()
            }
            .store(in: &cancellables)
    }

    private func updateRegistration() {
        let enabled = SettingsManager.shared.isVoiceShortcutEnabled
        let valid = SettingsManager.shared.voiceShortcut.isValid
        let shortcutDesc = SettingsManager.shared.voiceShortcut.displayString
        DMLogger.log("updateRegistration enabled=\(enabled) valid=\(valid) shortcut=\(shortcutDesc)", name: "GlobalShortcut")
        if enabled && valid {
            register()
        } else {
            unregister()
        }
    }

    /// 注册全局按键监听（keyDown + keyUp）。重复调用无效。
    func register() {
        guard monitor == nil else {
            DMLogger.log("register skipped: monitor already exists", name: "GlobalShortcut")
            return
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }
        if monitor == nil {
            DMLogger.error("register failed: NSEvent.addGlobalMonitorForEvents returned nil (accessibility not granted?)", name: "GlobalShortcut")
        } else {
            DMLogger.log("register succeeded", name: "GlobalShortcut")
        }
    }

    /// 注销全局按键监听。
    func unregister() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            DMLogger.log("unregister succeeded", name: "GlobalShortcut")
        }
    }

    private func handle(event: NSEvent) {
        guard !event.isARepeat else {
            DMLogger.log("ignore repeat keyCode=\(event.keyCode) type=\(event.type.rawValue)", name: "GlobalShortcut")
            return
        }

        let shortcut = SettingsManager.shared.voiceShortcut
        let eventMods = event.modifierFlags.intersection(relevantFlags)
        let shortcutMods = shortcut.modifierFlags.intersection(relevantFlags)

        DMLogger.log("event keyCode=\(event.keyCode) type=\(event.type.rawValue) mods=\(eventMods.rawValue) expected keyCode=\(shortcut.keyCode) mods=\(shortcutMods.rawValue)", name: "GlobalShortcut")

        switch event.type {
        case .keyDown:
            guard event.keyCode == shortcut.keyCode,
                  eventMods == shortcutMods else {
                DMLogger.log("keyDown does not match shortcut", name: "GlobalShortcut")
                return
            }
            DMLogger.log("shortcut pressed, start listening", name: "GlobalShortcut")
            VoiceShortcutCoordinator.shared.startIfPossible()

        case .keyUp:
            // 只要松开的是配置键就结束聆听，不强制要求修饰键仍按住
            guard event.keyCode == shortcut.keyCode else {
                DMLogger.log("keyUp ignored: different key", name: "GlobalShortcut")
                return
            }
            DMLogger.log("shortcut released, stop listening", name: "GlobalShortcut")
            VoiceShortcutCoordinator.shared.stopIfListening()

        default:
            break
        }
    }
}
