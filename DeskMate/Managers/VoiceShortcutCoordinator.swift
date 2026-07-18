import Foundation
import AppKit

/// 语音快捷键流程协调器。
///
/// 长按触发：按下快捷键开始聆听并播放 listen 动画，松开按键结束录音并自动发送。
/// 与 AI 对话页内的语音按钮使用独立的 `SpeechRecognitionManager` 实例，避免状态冲突。
@MainActor
final class VoiceShortcutCoordinator {
    static let shared = VoiceShortcutCoordinator()

    private let speechManager = SpeechRecognitionManager()
    private var releaseFallbackTimer: Timer?
    private var accumulatedText = ""
    private var isListening = false

    private init() {
        setupSpeechCallbacks()
    }

    // MARK: - Public

    /// 在满足条件时启动一次语音聆听流程（长按开始）。
    func startIfPossible() {
        guard SettingsManager.shared.isVoiceShortcutEnabled else {
            DMLogger.log("startIfPossible aborted: shortcut disabled", name: "VoiceShortcut")
            return
        }
        guard SettingsManager.shared.voiceShortcut.isValid else {
            DMLogger.log("startIfPossible aborted: shortcut invalid", name: "VoiceShortcut")
            return
        }
        guard !isListening else {
            DMLogger.log("startIfPossible aborted: already listening", name: "VoiceShortcut")
            return
        }
        guard let appDelegate = AppDelegate.shared else {
            DMLogger.error("startIfPossible aborted: AppDelegate.shared is nil", name: "VoiceShortcut")
            return
        }
        guard appDelegate.isPetVisible else {
            DMLogger.log("startIfPossible aborted: pet not visible", name: "VoiceShortcut")
            return
        }
        guard !appDelegate.isConsoleOpen else {
            DMLogger.log("startIfPossible aborted: console already open", name: "VoiceShortcut")
            return
        }

        DMLogger.log("startIfPossible starting listening session", name: "VoiceShortcut")
        accumulatedText = ""
        isListening = true

        appDelegate.petViewModel?.startListeningAnimation()
        speechManager.startRecording()
    }

    /// 松开快捷键时调用：结束录音并等待识别结果后自动发送。
    func stopIfListening() {
        guard isListening else {
            DMLogger.log("stopIfListening ignored: not listening", name: "VoiceShortcut")
            return
        }
        DMLogger.log("stopIfListening released, stopping recording", name: "VoiceShortcut")

        speechManager.stopRecording()
        AppDelegate.shared?.petViewModel?.stopListeningAnimation()

        // 保险：若识别最终回调异常地未到达，5 秒后强制清理状态
        releaseFallbackTimer?.invalidate()
        releaseFallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DMLogger.log("release fallback timer fired", name: "VoiceShortcut")
            self?.stopAndReset()
        }
    }

    // MARK: - Speech callbacks

    private func setupSpeechCallbacks() {
        speechManager.onTranscription = { [weak self] text, isFinal in
            guard let self = self, self.isListening else {
                DMLogger.log("transcription ignored: not listening (isFinal=\(isFinal))", name: "VoiceShortcut")
                return
            }
            self.accumulatedText = text
            AppDelegate.shared?.petViewModel?.updateListeningTranscript(text)
            DMLogger.log("transcription text=\"\(text)\" isFinal=\(isFinal)", name: "VoiceShortcut")

            if isFinal {
                self.finalize()
            }
        }

        speechManager.onError = { [weak self] message in
            guard let self = self, self.isListening else { return }
            DMLogger.log("VoiceShortcut speech error: \(message)", name: "VoiceShortcut")
            VoiceShortcutErrorPresenter.shared.message = message
            self.stopAndReset()
        }
    }

    // MARK: - Finalize

    private func finalize() {
        DMLogger.log("finalize called", name: "VoiceShortcut")
        stopAndReset()

        let text = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        DMLogger.log("finalize trimmed text=\"\(text)\"", name: "VoiceShortcut")
        guard !text.isEmpty else {
            DMLogger.log("finalize aborted: empty text", name: "VoiceShortcut")
            return
        }

        if SettingsManager.shared.isVoiceShortcutScreenshotEnabled {
            DMLogger.log("finalize capturing full-screen screenshot", name: "VoiceShortcut")
            ImageAttachmentManager.shared.captureFullScreenScreenshot { [weak self] result in
                let attachment = try? result.get()
                DMLogger.log("finalize screenshot attachment=\(attachment != nil)", name: "VoiceShortcut")
                self?.deliver(text: text, screenshot: attachment)
            }
        } else {
            deliver(text: text, screenshot: nil)
        }
    }

    private func deliver(text: String, screenshot: ChatImageAttachment?) {
        DMLogger.log("deliver text=\"\(text)\" hasScreenshot=\(screenshot != nil)", name: "VoiceShortcut")
        AppDelegate.shared?.openConsole()
        MainViewModel.shared.switchNav("ai-chat")

        let chatVM = AiChatViewModel.shared
        chatVM.updateInput(text)
        if let screenshot = screenshot {
            chatVM.addImageAttachment(screenshot)
        }
        chatVM.sendMessage()
    }

    private func stopAndReset() {
        DMLogger.log("stopAndReset", name: "VoiceShortcut")
        releaseFallbackTimer?.invalidate()
        releaseFallbackTimer = nil
        isListening = false
        AppDelegate.shared?.petViewModel?.stopListeningAnimation()
    }
}
