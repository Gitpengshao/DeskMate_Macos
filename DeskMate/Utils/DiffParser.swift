import Foundation

/// 解析 Git unified diff 文本为结构化模型。
enum DiffParser {

    /// 解析完整 diff 输出（可包含多个文件）。
    static func parse(_ raw: String) -> GitDiff {
        var files: [DiffFile] = []
        // 使用 components(separatedBy: "\n") 而非 split：Swift 将 \r\n 视为单一 Character，
        // split 按 Character 比较无法分割 CRLF；components 按字符串分隔可正确保留行尾 \r，
        // 后续再用 strippingTrailingCR 剥离即可。
        let lines = raw.components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("diff --git ") {
                let file = parseFile(lines: lines, startIndex: &index)
                files.append(file)
            } else {
                index += 1
            }
        }

        return GitDiff(files: files)
    }

    // MARK: - File 级解析

    private static func parseFile(lines: [String], startIndex: inout Int) -> DiffFile {
        var oldPath = ""
        var newPath = ""
        var isNew = false
        var isDeleted = false
        var isBinary = false
        var hunks: [DiffHunk] = []

        // 解析 `diff --git a/... b/...`
        let diffLine = lines[startIndex]
        if let paths = parseDiffGitLine(diffLine) {
            oldPath = paths.old
            newPath = paths.new
        }
        startIndex += 1

        // 跳过文件元数据行，直到出现 hunk 或下一个文件
        while startIndex < lines.count {
            let line = lines[startIndex]

            if line.hasPrefix("diff --git ") {
                // 进入下一个文件
                break
            }

            if line.hasPrefix("@@") {
                // 开始解析 hunks
                hunks = parseHunks(lines: lines, startIndex: &startIndex)
                break
            }

            if line.hasPrefix("new file mode") {
                isNew = true
            } else if line.hasPrefix("deleted file mode") {
                isDeleted = true
            } else if line.hasPrefix("Binary files") || line.hasPrefix("GIT binary patch") {
                isBinary = true
            } else if line.hasPrefix("similarity index") || line.hasPrefix("rename from") || line.hasPrefix("rename to") {
                // 重命名信息暂不展开，保留 oldPath/newPath
            }

            startIndex += 1
        }

        return DiffFile(
            oldPath: oldPath,
            newPath: newPath,
            hunks: hunks,
            isNew: isNew,
            isDeleted: isDeleted,
            isBinary: isBinary
        )
    }

    private static func parseDiffGitLine(_ line: String) -> (old: String, new: String)? {
        // 格式：diff --git a/<old> b/<new>
        // 兼容文件名中包含空格的情况：Git 会加引号，如 "a/path with spaces" "b/path with spaces"
        let trimmed = line.dropFirst("diff --git ".count)
        let text = String(trimmed)

        // 统一去除首尾引号（Git 对含特殊字符的路径会加引号）
        func unquote(_ s: String) -> String {
            var result = s
            if result.hasPrefix("\"") { result.removeFirst() }
            if result.hasSuffix("\"") { result.removeLast() }
            return result
        }

        // 按 " b/" 最后一次出现的位置分割，兼容路径中包含 " a/" 子串的情况
        if let range = text.range(of: " b/", options: .backwards) {
            let oldPart = unquote(String(text[..<range.lowerBound]))
            let newPart = unquote(String(text[range.upperBound...]))
            let old = oldPart.hasPrefix("a/") ? String(oldPart.dropFirst(2)) : oldPart
            let new = newPart
            return (old: old, new: new)
        }

        // 回退：简单按空格分割并去引号
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let old = unquote(String(parts[0])).hasPrefix("a/")
            ? String(unquote(String(parts[0])).dropFirst(2))
            : unquote(String(parts[0]))
        let new = unquote(String(parts[1])).hasPrefix("b/")
            ? String(unquote(String(parts[1])).dropFirst(2))
            : unquote(String(parts[1]))
        return (old: old, new: new)
    }

    // MARK: - Hunk 级解析

    private static func parseHunks(lines: [String], startIndex: inout Int) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var hunkIndex = 0

        while startIndex < lines.count {
            let line = lines[startIndex]

            if line.hasPrefix("diff --git ") || line.hasPrefix("-- ") {
                break
            }

            if line.hasPrefix("@@") {
                let hunk = parseHunk(lines: lines, startIndex: &startIndex, hunkIndex: hunkIndex)
                hunks.append(hunk)
                hunkIndex += 1
            } else {
                startIndex += 1
            }
        }

        return hunks
    }

    private static func parseHunk(lines: [String], startIndex: inout Int, hunkIndex: Int) -> DiffHunk {
        let headerLine = lines[startIndex]
        var oldStart = 0
        var oldCount = 0
        var newStart = 0
        var newCount = 0

        if let info = parseHunkHeader(headerLine) {
            oldStart = info.oldStart
            oldCount = info.oldCount
            newStart = info.newStart
            newCount = info.newCount
        }

        var hunkLines: [DiffLine] = []
        // 第一行是 hunk 头本身
        hunkLines.append(DiffLine(
            kind: .hunkHeader,
            text: headerLine,
            oldLineNumber: nil,
            newLineNumber: nil,
            hunkIndex: hunkIndex,
            lineIndexInHunk: 0
        ))

        startIndex += 1
        var oldLine = oldStart
        var newLine = newStart
        var lineIndexInHunk = 1
        // 根据 hunk 头声明的行数控制解析终止，避免把 diff 文本末尾的空行误判为上下文。
        var remainingOld = oldCount
        var remainingNew = newCount

        while startIndex < lines.count && (remainingOld > 0 || remainingNew > 0) {
            let raw = lines[startIndex]

            if raw.hasPrefix("diff --git ") || raw.hasPrefix("@@") || raw.hasPrefix("-- ") {
                break
            }

            let kind: DiffLineKind
            let content: String
            var oldNumber: Int? = nil
            var newNumber: Int? = nil

            if raw.hasPrefix("\\ ") {
                kind = .noNewlineAtEnd
                content = raw
            } else if raw.hasPrefix("+") {
                guard remainingNew > 0 else { break }
                kind = .added
                content = String(raw.dropFirst())
                newNumber = newLine
                newLine += 1
                remainingNew -= 1
            } else if raw.hasPrefix("-") {
                guard remainingOld > 0 else { break }
                kind = .deleted
                content = String(raw.dropFirst())
                oldNumber = oldLine
                oldLine += 1
                remainingOld -= 1
            } else if raw.hasPrefix(" ") {
                guard remainingOld > 0 && remainingNew > 0 else { break }
                kind = .context
                content = String(raw.dropFirst())
                oldNumber = oldLine
                newLine += 1
                oldLine += 1
                remainingOld -= 1
                remainingNew -= 1
            } else {
                // 非标准行（如 diff 文本末尾的空行），不再当作上下文处理。
                break
            }

            let normalizedContent = strippingTrailingCR(content)

            hunkLines.append(DiffLine(
                kind: kind,
                text: normalizedContent,
                oldLineNumber: oldNumber,
                newLineNumber: newNumber,
                hunkIndex: hunkIndex,
                lineIndexInHunk: lineIndexInHunk
            ))
            lineIndexInHunk += 1
            startIndex += 1
        }

        return DiffHunk(
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            header: headerLine,
            lines: hunkLines
        )
    }

    /// 解析 hunk 头 `@@ -oldStart,oldCount +newStart,newCount @@`。
    /// 兼容省略计数的情况，例如 `@@ -1 +1 @@`。
    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
        let pattern = #"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else { return nil }

        let oldStart = Int((line as NSString).substring(with: match.range(at: 1))) ?? 0
        let oldCountStr = match.range(at: 2).location != NSNotFound ? (line as NSString).substring(with: match.range(at: 2)) : "1"
        let oldCount = Int(oldCountStr) ?? 1

        let newStart = Int((line as NSString).substring(with: match.range(at: 3))) ?? 0
        let newCountStr = match.range(at: 4).location != NSNotFound ? (line as NSString).substring(with: match.range(at: 4)) : "1"
        let newCount = Int(newCountStr) ?? 1

        return (oldStart: max(0, oldStart), oldCount: oldCount, newStart: max(0, newStart), newCount: newCount)
    }

    /// 去除 Git diff 行尾残留的 \r（CRLF 文件在按 \n 分割后会留下 \r）。
    private static func strippingTrailingCR(_ text: String) -> String {
        if text.hasSuffix("\r") {
            return String(text.dropLast())
        }
        return text
    }
}
