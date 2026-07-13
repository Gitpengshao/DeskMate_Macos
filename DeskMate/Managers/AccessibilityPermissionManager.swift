import Foundation
import ApplicationServices

/// 辅助功能权限管理 —— 全局快捷键监听需要此权限。
@MainActor
final class AccessibilityPermissionManager {
    static let shared = AccessibilityPermissionManager()

    private init() {}

    /// 当前是否已获得辅助功能权限。
    var isTrusted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// 主动弹出系统授权提示（若未授权）。
    func promptIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
