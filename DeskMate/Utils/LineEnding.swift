import Foundation

/// 统一处理文本换行符的工具，避免 `String.split { $0.isNewline }` 在 `\r\n` 上产生空行碎片。
enum LineEnding {
    /// 检测文本中使用的主要换行符。
    static func detect(in text: String) -> String {
        if text.contains("\r\n") { return "\r\n" }
        if text.contains("\r") { return "\r" }
        return "\n"
    }

    /// 按检测到的换行符分割文本。
    ///
    /// 若文本以换行符结尾，`components(separatedBy:)` 会产生一个末尾空字符串；
    /// 该空字符串仅代表末尾换行，不代表实际空行，因此会被移除。
    /// 调用方如需保留末尾换行，应使用 `joinLines(..., trailing: true)`。
    static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let separator = detect(in: text)
        var lines = text.components(separatedBy: separator)
        if lines.last?.isEmpty == true && text.hasSuffix(separator) {
            lines.removeLast()
        }
        return lines
    }

    /// 使用指定换行符拼接行，可选保留末尾换行。
    static func joinLines(_ lines: [String], ending: String, trailing: Bool) -> String {
        var result = lines.joined(separator: ending)
        if trailing && !result.isEmpty {
            result.append(ending)
        }
        return result
    }
}
