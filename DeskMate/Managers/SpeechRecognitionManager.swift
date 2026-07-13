import Foundation
import Combine
import Speech
@preconcurrency import AVFAudio

/// 语音识别状态。
enum SpeechRecognitionState: Equatable {
    case idle
    case requestingPermission
    case starting
    case recording
    case stopping
    case error(String)
}

/// 本地语音识别管理器 —— 基于 macOS 原生 Speech / AVAudioEngine。
///
/// - 完全本地、免费，无需网络或 API 密钥。
/// - 使用 `SFSpeechAudioBufferRecognitionRequest` 流式识别，不落地音频文件。
/// - 通过 `AVAudioEngine.inputNode` 直接读取麦克风 PCM buffer，低延迟高性能。
final class SpeechRecognitionManager: NSObject, ObservableObject {
    static let shared = SpeechRecognitionManager()

    @Published private(set) var state: SpeechRecognitionState = .idle
    @Published private(set) var transcribedText: String = ""

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "com.deskmate.speech.audio", qos: .userInitiated)

    /// 识别到文本后的回调（每次 partial / final 都会触发，final 时 `isFinal == true`）。
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?

    override init() {
        let preferredLocale = Locale(identifier: "zh-Hans")
        self.speechRecognizer = SFSpeechRecognizer(locale: preferredLocale)
        super.init()
        self.speechRecognizer?.delegate = self
    }

    // MARK: - Permissions

    /// 查询并请求麦克风 + 语音识别权限。
    ///
    /// - Returns: 是否已获得全部权限；如果权限未决定，会弹出系统授权弹窗。
    func requestPermissions() async -> Bool {
        await MainActor.run { state = .requestingPermission }

        let micStatus = await requestMicrophonePermission()
        guard micStatus == .authorized else {
            let message = micStatus == .denied
                ? "麦克风权限被拒绝，请在系统设置 › 隐私与安全性 › 麦克风中开启。"
                : "无法获取麦克风权限。"
            await MainActor.run { state = .error(message) }
            await MainActor.run { onError?(message) }
            return false
        }

        let speechStatus = await requestSpeechRecognitionPermission()
        guard speechStatus == .authorized else {
            let message = speechStatus == .denied
                ? "语音识别权限被拒绝，请在系统设置 › 隐私与安全性 › 语音识别中开启。"
                : "无法获取语音识别权限。"
            await MainActor.run { state = .error(message) }
            await MainActor.run { onError?(message) }
            return false
        }

        return true
    }

    private func requestMicrophonePermission() async -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    continuation.resume(returning: AVCaptureDevice.authorizationStatus(for: .audio))
                }
            }
        }
        return status
    }

    private func requestSpeechRecognitionPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in
                    continuation.resume(returning: SFSpeechRecognizer.authorizationStatus())
                }
            }
        }
        return status
    }

    // MARK: - Recording

    /// 开始录音并实时转写。
    @MainActor
    func startRecording() {
        guard state != .recording && state != .starting else { return }
        Task {
            let permitted = await requestPermissions()
            guard permitted else { return }
            await startRecordingUnsafe()
        }
    }

    /// 停止录音，并在回调中返回最终转写文本。
    func stopRecording() {
        guard state == .recording || state == .starting else { return }

        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.audioEngine.stop()
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.recognitionRequest?.endAudio()

            Task { @MainActor in
                if case .error = self.state { return }
                self.state = .stopping
            }
        }
    }

    /// 立即停止并丢弃当前识别结果。
    func cancelRecording() {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.audioEngine.stop()
            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.recognitionRequest?.endAudio()
            self.recognitionTask?.cancel()

            Task { @MainActor in
                self.state = .idle
                self.transcribedText = ""
            }
        }
    }

    @MainActor
    private func startRecordingUnsafe() async {
        state = .starting

        do {
            // 重置上一次任务
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            transcribedText = ""

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true // 强制本地识别，无需网络
            self.recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                throw NSError(domain: "SpeechRecognitionManager", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "无法获取麦克风音频格式"])
            }

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                Task { @MainActor in
                    if let result = result {
                        self.transcribedText = result.bestTranscription.formattedString
                        self.onTranscription?(self.transcribedText, result.isFinal)
                    }

                    if result?.isFinal == true || error != nil {
                        self.cleanupAfterRecognition()
                        if let error = error, (error as NSError).code != 203 {
                            // 203 通常为手动停止后的正常超时，忽略
                            let message = self.formattedError(error)
                            self.state = .error(message)
                            self.onError?(message)
                        } else {
                            self.state = .idle
                        }
                    } else {
                        self.state = .recording
                    }
                }
            }

            audioQueue.async { [weak self] in
                guard let self = self else { return }
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
                    self.recognitionRequest?.append(buffer)
                }
                self.audioEngine.prepare()
                try? self.audioEngine.start()
            }

        } catch {
            let message = formattedError(error)
            state = .error(message)
            onError?(message)
        }
    }

    private func cleanupAfterRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func formattedError(_ error: Error) -> String {
        let nsError = error as NSError
        let description = error.localizedDescription.lowercased()

        // 系统听写被关闭时的明确提示；该错误不会进入 domain/code 分支，需通过文本匹配。
        if description.contains("dictation") || description.contains("siri") {
            return "系统听写未开启。请在系统设置 › 键盘 › 听写中打开听写功能。"
        }

        switch nsError.domain {
        case "kAFAssistantErrorDomain", "com.apple.speech.recognition.error":
            switch nsError.code {
            case 1: return "语音识别被用户取消。"
            case 2: return "语音识别不可用。"
            case 3: return "语音识别遇到网络问题。"
            case 4: return "麦克风无音频输入，请检查设备。"
            case 203: return "语音识别超时，请重试。"
            default: return "语音识别失败：\(error.localizedDescription)"
            }
        default:
            return "语音识别失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechRecognitionManager: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available && self.state == .recording {
                self.stopRecording()
                let message = "当前语言语音识别不可用。"
                self.state = .error(message)
                self.onError?(message)
            }
        }
    }
}
