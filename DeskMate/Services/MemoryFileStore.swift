import Foundation

/// 记忆文件存储服务 — 一比一还原 Flutter 的 § 段分隔逻辑。
///
/// 文件格式（与 hermes-agent `memory_tool.py` 行为一致）：
/// ```
/// 第一条记忆内容
/// §
/// 第二条记忆内容
/// §
/// 第三条记忆内容
/// ```
///
/// - MEMORY.md — Agent 永久记忆（位于 `~/.hermes/memories/MEMORY.md`）
/// - USER.md   — 用户偏好（位于 `~/.hermes/memories/USER.md`）
nonisolated final class MemoryFileStore {

    // MARK: - File names

    private let memoryFileName = "MEMORY.md"
    private let userFileName   = "USER.md"

    /// § 段分隔符，与 Flutter 一致。
    private let sectionSeparator = "§"

    // MARK: - Public API

    /// 读取指定目标的所有记忆条目。
    func readEntries(_ target: MemoryTarget) throws -> [MemoryEntry] {
        let url = try resolveFileURL(target)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
        let parts = parseEntries(raw)
        return toEntries(parts, target: target)
    }

    /// 将条目列表写回文件。条目为空时删除文件。
    func writeEntries(_ target: MemoryTarget, entries: [MemoryEntry]) throws {
        let url = try resolveFileURL(target)
        if entries.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        let parts = entries.map { $0.content }
        let formatted = formatEntries(parts)
        try formatted.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Format helpers

    /// 拆分原始文件内容为独立条目（去空白、忽略空段）。
    func parseEntries(_ raw: String) -> [String] {
        // 与 Flutter 端保持一致：`\n?§\n?`
        let separatorPattern = "\\n?§\\n?"
        guard let regex = try? NSRegularExpression(pattern: separatorPattern) else {
            return []
        }
        let range = NSRange(raw.startIndex..., in: raw)
        let matches = regex.matches(in: raw, range: range)

        var results: [String] = []
        var cursor = raw.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: raw) else { continue }
            let part = String(raw[cursor..<matchRange.lowerBound])
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                results.append(trimmed)
            }
            cursor = matchRange.upperBound
        }
        let tail = String(raw[cursor...])
        let trimmedTail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTail.isEmpty {
            results.append(trimmedTail)
        }
        return results
    }

    /// 将条目列表拼接为 `§` 分隔的字符串。
    func formatEntries(_ entries: [String]) -> String {
        return entries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\(sectionSeparator)\n")
    }

    // MARK: - Private

    private func toEntries(_ parts: [String], target: MemoryTarget) -> [MemoryEntry] {
        var entries: [MemoryEntry] = []
        for (i, p) in parts.enumerated() {
            entries.append(MemoryEntry(target: target, index: i, content: p))
        }
        return entries
    }

    /// 解析目标文件 URL，确保父目录存在。
    private func resolveFileURL(_ target: MemoryTarget) throws -> URL {
        let hermesHome = AppConstants.resolveHermesHome()
        let memDir = URL(fileURLWithPath: hermesHome)
            .appendingPathComponent("memories", isDirectory: true)
        if !FileManager.default.fileExists(atPath: memDir.path) {
            try FileManager.default.createDirectory(
                at: memDir,
                withIntermediateDirectories: true
            )
        }
        let fileName = (target == .memory) ? memoryFileName : userFileName
        return memDir.appendingPathComponent(fileName)
    }
}
