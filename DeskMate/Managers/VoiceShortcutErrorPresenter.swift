import Foundation
import Combine

/// 语音快捷键流程中的错误展示桥接。
///
/// 由于流程可能在控制台未打开时触发，无法直接弹窗，因此通过单例 ObservableObject
/// 把错误透传给设置页等已有 UI 进行提示。
@MainActor
final class VoiceShortcutErrorPresenter: ObservableObject {
    static let shared = VoiceShortcutErrorPresenter()

    @Published var message: String?

    private init() {}
}
