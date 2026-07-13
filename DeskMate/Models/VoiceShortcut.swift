import Foundation
import AppKit

/// 用户录制的全局语音快捷键。
struct VoiceShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifierFlagsRaw: UInt

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRaw)
    }

    init(keyCode: UInt16 = 0, modifierFlags: NSEvent.ModifierFlags = []) {
        self.keyCode = keyCode
        self.modifierFlagsRaw = modifierFlags.rawValue
    }

    /// 是否已设置有效快捷键（至少包含一个修饰键和一个普通键）。
    var isValid: Bool {
        keyCode != 0 && !modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
    }

    /// 用于设置页展示，例如 "⌘⇧L"。
    var displayString: String {
        var result = ""
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { result += "⌘" }
        if flags.contains(.option)  { result += "⌥" }
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.shift)   { result += "⇧" }
        result += Self.keyCodeDisplayName(keyCode)
        return result
    }

    /// 常见 key code 到可读名称的映射表。
    private static func keyCodeDisplayName(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F",
            0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
            0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
            0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2",
            0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
            0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-",
            0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O",
            0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K",
            0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/",
            0x2D: "N", 0x2E: "M", 0x2F: ".",
            0x30: "Tab", 0x31: "Space", 0x24: "Return",
            0x35: "Esc", 0x33: "Backspace",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
            0x72: "F1", 0x73: "F2", 0x74: "F3", 0x75: "F4",
            0x76: "F5", 0x77: "F6", 0x78: "F7", 0x79: "F8",
            0x7A: "F9", 0x43: "F10", 0x44: "F11", 0x45: "F12"
        ]
        return map[code] ?? "Key \(code)"
    }
}
