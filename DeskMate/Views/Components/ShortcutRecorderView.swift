import SwiftUI
import Combine
import AppKit

/// 快捷键录制组件：点击录制后捕获用户的组合键，保存为 `VoiceShortcut`。
struct ShortcutRecorderView: View {
    @Binding var shortcut: VoiceShortcut
    @StateObject private var recorder = ShortcutRecorderState()

    var body: some View {
        HStack(spacing: 10) {
            Text(recorder.isRecording ? "请按下快捷键…" : (shortcut.isValid ? shortcut.displayString : "未设置"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(shortcut.isValid ? Palette.textPrimary : Palette.textTertiary)
                .frame(minWidth: 80, alignment: .leading)

            Button(action: {
                recorder.isRecording ? recorder.stop() : recorder.start()
            }) {
                Text(recorder.isRecording ? "取消" : "录制")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.inverseInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Palette.inverse)
                    )
            }
            .buttonStyle(.plain)

            if shortcut.isValid {
                Button(action: {
                    shortcut = VoiceShortcut()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Palette.textSecond)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.bgPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(recorder.isRecording ? Palette.textPrimary : Palette.border, lineWidth: 1)
                )
        )
        .onAppear {
            recorder.onCaptured = { captured in
                shortcut = captured
            }
        }
        .onDisappear {
            recorder.stop()
        }
    }
}

// MARK: - Recorder state

@MainActor
private final class ShortcutRecorderState: ObservableObject {
    @Published var isRecording = false
    private var localMonitor: Any?
    var onCaptured: ((VoiceShortcut) -> Void)?

    private let modifierKeyCodes: Set<UInt16> = [
        0x37, // Command
        0x38, // Shift
        0x3A, // Option
        0x3B, // Control
        0x39  // Caps Lock
    ]

    func start() {
        guard !isRecording else { return }
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        // Esc 取消录制
        if event.keyCode == 0x35 {
            stop()
            return
        }

        // 拒绝单独的修饰键
        guard !modifierKeyCodes.contains(event.keyCode) else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isEmpty else { return }

        onCaptured?(VoiceShortcut(keyCode: event.keyCode, modifierFlags: flags))
        stop()
    }
}

// MARK: - Palette

private enum Palette {
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
    static let inverse     = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let inverseInk  = Color(red: 0.000, green: 0.000, blue: 0.000)
}
