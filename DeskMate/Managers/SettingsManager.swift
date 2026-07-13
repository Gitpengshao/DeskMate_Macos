import SwiftUI
import Combine

/// 全局应用设置存储，通过 UserDefaults 持久化，可被设置页与桌宠窗口共享。
@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    /// 桌宠尺寸缩放比例（基于原始精灵帧大小）。
    @Published var petSizeScale: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(petSizeScale), forKey: SettingsKeys.petSizeScale)
        }
    }

    /// 鼠标悬浮桌宠时是否使其透明并忽略鼠标事件，避免遮挡其他软件。
    @Published var isHoverTransparentEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHoverTransparentEnabled, forKey: SettingsKeys.hoverTransparentEnabled)
        }
    }

    /// 是否启用全局语音聆听快捷键。
    @Published var isVoiceShortcutEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVoiceShortcutEnabled, forKey: SettingsKeys.voiceShortcutEnabled)
        }
    }

    /// 当前设置的全局语音快捷键。
    @Published var voiceShortcut: VoiceShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(voiceShortcut) {
                UserDefaults.standard.set(data, forKey: SettingsKeys.voiceShortcut)
            }
        }
    }

    /// 语音快捷键触发后是否同时发送当前桌面截图。
    @Published var isVoiceShortcutScreenshotEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVoiceShortcutScreenshotEnabled, forKey: SettingsKeys.voiceShortcutScreenshotEnabled)
        }
    }

    /// 根据当前缩放比例计算的实际桌宠尺寸。
    var petSize: CGSize {
        CGSize(width: SpriteSheets.frameSize * petSizeScale,
               height: SpriteSheets.frameSize * petSizeScale)
    }

    /// 应用版本号（例如 "1.0"）。
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private init() {
        let storedScale = UserDefaults.standard.double(forKey: SettingsKeys.petSizeScale)
        self.petSizeScale = storedScale > 0 ? CGFloat(storedScale) : 1.0
        self.isHoverTransparentEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.hoverTransparentEnabled)
        self.isVoiceShortcutEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.voiceShortcutEnabled)
        self.isVoiceShortcutScreenshotEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.voiceShortcutScreenshotEnabled)

        if let data = UserDefaults.standard.data(forKey: SettingsKeys.voiceShortcut),
           let shortcut = try? JSONDecoder().decode(VoiceShortcut.self, from: data) {
            self.voiceShortcut = shortcut
        } else {
            self.voiceShortcut = VoiceShortcut()
        }
    }
}

// MARK: - Keys

private enum SettingsKeys {
    static let petSizeScale = "desk_mate_pet_size_scale"
    static let hoverTransparentEnabled = "desk_mate_hover_transparent_enabled"
    static let voiceShortcutEnabled = "desk_mate_voice_shortcut_enabled"
    static let voiceShortcut = "desk_mate_voice_shortcut"
    static let voiceShortcutScreenshotEnabled = "desk_mate_voice_shortcut_screenshot_enabled"
}
