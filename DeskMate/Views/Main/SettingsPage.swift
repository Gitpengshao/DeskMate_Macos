import SwiftUI
import AVFoundation
import Speech

/// 设置页面 — 展示版本号、桌宠大小与悬浮透明等配置项。
struct SettingsPage: View {
    @StateObject private var settings = SettingsManager.shared

    @StateObject private var errorPresenter = VoiceShortcutErrorPresenter.shared

    @State private var accessibilityTrusted = false
    @State private var voiceAuthorized = false
    @State private var screenRecordingAuthorized = false
    @State private var alertMessage: String?

    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 2.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                versionSection
                Divider()
                    .background(Palette.border)
                petSizeSection
                Divider()
                    .background(Palette.border)
                hoverTransparencySection
                Divider()
                    .background(Palette.border)
                voiceShortcutSection

                Spacer()
            }
            .padding(28)
        }
        .background(Palette.bgBase)
        .onAppear(perform: refreshPermissionStatus)
        .alert("权限提示", isPresented: .constant(alertMessage != nil)) {
            Button("确定") { alertMessage = nil }
            Button("打开系统设置") {
                alertMessage = nil
                openSystemPreferences()
            }
        } message: {
            Text(alertMessage ?? "")
        }
        .alert("语音快捷键", isPresented: Binding<Bool>(
            get: { errorPresenter.message != nil },
            set: { if !$0 { errorPresenter.message = nil } }
        )) {
            Button("确定") { errorPresenter.message = nil }
            if let message = errorPresenter.message, message.contains("听写") {
                Button("打开键盘设置") {
                    errorPresenter.message = nil
                    openKeyboardDictationSettings()
                }
            }
        } message: {
            Text(errorPresenter.message ?? "")
        }
    }

    // MARK: - Version Section

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.textPrimary)

            HStack(spacing: 12) {
                Image("applogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DeskMate")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)

                    Text("版本 \(settings.appVersion)")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textSecond)
                }

                Spacer()
            }
            .padding(14)
            .background(Palette.bgPanel)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Palette.border, lineWidth: 1)
            )
            .cornerRadius(10)
        }
    }

    // MARK: - Pet Size Section

    private var petSizeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("桌宠大小")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)

                Spacer()

                Text(String(format: "%.0f%%", settings.petSizeScale * 100))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.textSecond)
                    .frame(minWidth: 44, alignment: .trailing)
            }

            HStack(spacing: 12) {
                Text("小")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textTertiary)

                Slider(value: $settings.petSizeScale, in: minScale...maxScale, step: 0.1)
                    .tint(Palette.textPrimary)

                Text("大")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
            }

            Text("拖动滑块调整桌宠显示尺寸，更改会立即生效。")
                .font(.system(size: 11))
                .foregroundColor(Palette.textTertiary)
        }
    }

    // MARK: - Hover Transparency Section

    private var hoverTransparencySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("悬浮时透明")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)

                    Text("鼠标悬浮在桌宠上时自动变透明并忽略点击，防止遮挡其他软件。")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $settings.isHoverTransparentEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: Palette.textPrimary))
                    .labelsHidden()
                    .frame(width: 44)
            }
        }
    }

    // MARK: - Voice Shortcut Section

    private var voiceShortcutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("语音聆听快捷键")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.textPrimary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("启用全局语音快捷键")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)

                    Text("桌宠可见且控制台关闭时，按住快捷键开始录音，松手后结束并发送。")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $settings.isVoiceShortcutEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: Palette.textPrimary))
                    .labelsHidden()
                    .frame(width: 44)
                    .disabled(!settings.voiceShortcut.isValid)
                    .onChange(of: settings.isVoiceShortcutEnabled) { _, isOn in
                        if isOn {
                            Task { await handleEnableVoiceShortcut() }
                        }
                    }
            }

            HStack(spacing: 12) {
                Text("快捷键")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecond)

                ShortcutRecorderView(shortcut: $settings.voiceShortcut)

                Spacer()
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("同时发送当前桌面截图")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)

                    Text("开启后，语音发送时会附加主显示器桌面截图。")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $settings.isVoiceShortcutScreenshotEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: Palette.textPrimary))
                    .labelsHidden()
                    .frame(width: 44)
                    .onChange(of: settings.isVoiceShortcutScreenshotEnabled) { _, isOn in
                        if isOn {
                            handleEnableScreenshot()
                        }
                    }
            }

            permissionStatusView

            Text("快捷键仅在桌宠可见且控制台关闭时生效；按住快捷键开始聆听，松手后自动结束并发送。")
                .font(.system(size: 11))
                .foregroundColor(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Permission Status

    private var permissionStatusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("权限状态")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Palette.textPrimary)

            HStack(spacing: 16) {
                PermissionRow(label: "辅助功能", granted: accessibilityTrusted)
                PermissionRow(label: "麦克风", granted: voiceAuthorized)
                PermissionRow(label: "屏幕录制", granted: screenRecordingAuthorized)
            }

            HStack(spacing: 8) {
                Button("检查权限") {
                    refreshPermissionStatus()
                }
                .font(.system(size: 11))

                Button("打开系统设置") {
                    openSystemPreferences()
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(Palette.textSecond)
        }
    }

    // MARK: - Permission Helpers

    private func refreshPermissionStatus() {
        accessibilityTrusted = AccessibilityPermissionManager.shared.isTrusted
        screenRecordingAuthorized = ImageAttachmentManager.shared.checkScreenRecordingPermission()

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        voiceAuthorized = micStatus == .authorized && speechStatus == .authorized
    }

    private func handleEnableVoiceShortcut() async {
        guard settings.voiceShortcut.isValid else {
            settings.isVoiceShortcutEnabled = false
            alertMessage = "请先录制一个有效的快捷键。"
            return
        }

        AccessibilityPermissionManager.shared.promptIfNeeded()
        let voiceOK = await SpeechRecognitionManager.shared.requestPermissions()

        await MainActor.run {
            refreshPermissionStatus()
            if !voiceOK {
                settings.isVoiceShortcutEnabled = false
                alertMessage = "需要麦克风与语音识别权限才能使用语音快捷键。"
            } else if !AccessibilityPermissionManager.shared.isTrusted {
                alertMessage = "需要辅助功能权限才能监听全局快捷键，请授权后重新开启。"
            }
        }
    }

    private func handleEnableScreenshot() {
        let granted = ImageAttachmentManager.shared.requestScreenRecordingPermission()
        refreshPermissionStatus()
        if !granted {
            settings.isVoiceShortcutScreenshotEnabled = false
            alertMessage = "需要屏幕录制权限才能发送桌面截图。"
        }
    }

    private func openSystemPreferences() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openKeyboardDictationSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.keyboard?Dictation"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let label: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(granted ? Color(red: 0.30, green: 0.85, blue: 0.40) : Color(red: 0.95, green: 0.30, blue: 0.30))

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Palette.textSecond)
        }
    }
}

// MARK: - Palette

private enum Palette {
    static let bgBase      = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
}

// MARK: - Preview

#if DEBUG
struct SettingsPage_Previews: PreviewProvider {
    static var previews: some View {
        SettingsPage()
            .frame(width: 700, height: 500)
    }
}
#endif
