import Foundation

/// 把 assistant 的原始文本解析为类型化的 `ContentBlock` 数组。
///
/// 参考 hermes-studio 的 `thinking-parser.ts`：先保护代码块，再提取
/// `<think>` / `<thinking>` / `<reasoning>` 标签，最后恢复代码块。
enum ChatContentParser {

    // MARK: - Public API

    /// 解析 assistant 文本，返回类型化的内容块。
    /// - Parameters:
    ///   - text: 原始文本（可能包含 <think> 标签和工具结果 JSON）。
    ///   - streaming: 是否流式中；流式模式下未闭合的 <think> 标签内容作为 pending reasoning。
    static func parseContentBlocks(from text: String, streaming: Bool) -> [ContentBlock] {
        let protected = protectCodeBlocks(text)
        let parsed = parseThinking(masked: protected.masked, streaming: streaming)

        var blocks: [ContentBlock] = []

        // Reasoning 段
        for segment in parsed.segments {
            let restored = restoreCodeBlocks(segment, blocks: protected.blocks)
            blocks.append(.reasoning(text: restored, isPending: false))
        }

        // 流式 pending reasoning
        if let pending = parsed.pending {
            let restored = restoreCodeBlocks(pending, blocks: protected.blocks)
            blocks.append(.reasoning(text: restored, isPending: true))
        }

        // 正文 + 工具结果 JSON（在 masked body 上解析，内部再恢复代码块）
        let bodyBlocks = parseBodyBlocks(from: parsed.body, codeBlocks: protected.blocks)
        blocks.append(contentsOf: bodyBlocks)

        return blocks
    }

    /// 根据工具名与参数推断文件改动。
    static func detectFileChanges(toolName: String, arguments: [String: Any]) -> [FileChangeBlock] {
        let normalized = toolName.lowercased()

        switch normalized {
        case "write_file":
            if let path = stringArgument(from: arguments, keys: ["path", "file_path", "filename"]) {
                let content = arguments["content"] as? String
                return [.init(id: "fc-write-\(path)", path: path, operation: .modify, additions: nil, deletions: nil, newContent: content)]
            }
        case "create_file":
            if let path = stringArgument(from: arguments, keys: ["path", "file_path", "filename"]) {
                let content = arguments["content"] as? String
                return [.init(id: "fc-create-\(path)", path: path, operation: .add, additions: nil, deletions: nil, newContent: content)]
            }
        case "apply_diff":
            if let path = stringArgument(from: arguments, keys: ["path", "file_path", "filename"]) {
                var additions: Int?
                var deletions: Int?
                if let diff = arguments["diff"] as? String {
                    let counts = countDiffLines(diff)
                    additions = counts.additions
                    deletions = counts.deletions
                }
                return [.init(id: "fc-diff-\(path)", path: path, operation: .modify, additions: additions, deletions: deletions, newContent: nil)]
            }
        case "delete_file", "delete":
            if let path = stringArgument(from: arguments, keys: ["path", "file_path", "filename"]) {
                return [.init(id: "fc-delete-\(path)", path: path, operation: .delete, additions: nil, deletions: nil, newContent: nil)]
            }
        case "shell":
            if let command = stringArgument(from: arguments, keys: ["command", "cmd", "shell_command"]) {
                return fileChangesFromShellCommand(command)
            }
        default:
            break
        }

        return []
    }

    /// 解析历史中的 assistant 消息：reasoning + 正文 + tool_calls。
    static func parseAssistantMessage(
        content: String,
        reasoning: String,
        toolCalls: Any?
    ) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let cleanedReasoning = reasoning
            .replacingOccurrences(of: "<null>", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedReasoning = cleanedReasoning.lowercased()
        let isPlaceholderReasoning = cleanedReasoning.isEmpty
            || lowercasedReasoning == "null"
            || lowercasedReasoning == "nil"
        if !isPlaceholderReasoning {
            blocks.append(.reasoning(text: cleanedReasoning, isPending: false))
        }

        let textBlocks = parseContentBlocks(from: content, streaming: false)
        blocks.append(contentsOf: textBlocks)

        if let calls = toolCalls as? [[String: Any]] {
            for tc in calls {
                guard let fn = tc["function"] as? [String: Any] else { continue }
                let id = tc["id"] as? String ?? UUID().uuidString
                let name = fn["name"] as? String ?? "unknown"
                let argsStr = fn["arguments"] as? String ?? "{}"
                var arguments: [String: Any] = ["raw": argsStr]
                if let data = argsStr.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    arguments = parsed
                }

                let displayArgs: String
                if let data = try? JSONSerialization.data(withJSONObject: arguments, options: .sortedKeys),
                   let json = String(data: data, encoding: .utf8) {
                    displayArgs = json
                } else {
                    displayArgs = argsStr
                }

                blocks.append(.toolCall(ToolCallBlock(
                    id: id,
                    name: name,
                    arguments: arguments,
                    displayArguments: displayArgs
                )))
                let fileChanges = detectFileChanges(toolName: name, arguments: arguments)
                blocks.append(contentsOf: fileChanges.map { .fileChange($0) })
            }
        }

        return blocks
    }

    /// 解析历史中的 tool 消息：把 JSON 内容拆成 observation + fileChange。
    static func parseToolMessage(content: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []

        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           looksLikeToolResult(json) {
            let (observation, fileChanges) = parseToolResultJSON(json, raw: content)
            blocks.append(.observation(observation))
            blocks.append(contentsOf: fileChanges.map { .fileChange($0) })
        } else {
            // 不是工具结果 JSON，按普通文本展示
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.text(trimmed))
            }
        }

        return blocks
    }

    // MARK: - Thinking parsing

    private struct ParsedThinking {
        let segments: [String]
        let pending: String?
        let body: String
    }

    private static func parseThinking(masked: String, streaming: Bool) -> ParsedThinking {
        var segments: [String] = []
        var body = ""
        var lastIndex = masked.startIndex

        let pattern = "<(think|thinking|reasoning)>(.*?)</\\1>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return ParsedThinking(segments: [], pending: nil, body: masked)
        }

        let nsRange = NSRange(masked.startIndex..., in: masked)
        let matches = regex.matches(in: masked, options: [], range: nsRange)

        for match in matches {
            let matchRange = Range(match.range, in: masked)!
            let before = String(masked[lastIndex..<matchRange.lowerBound])
            body.append(before)

            if let contentRange = Range(match.range(at: 2), in: masked) {
                segments.append(String(masked[contentRange]))
            }

            lastIndex = matchRange.upperBound
        }

        let rest = String(masked[lastIndex...])

        // 未闭合标签
        let openPattern = "<(think|thinking|reasoning)>(.*)$"
        if let openRegex = try? NSRegularExpression(pattern: openPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let openMatch = openRegex.firstMatch(in: rest, options: [], range: NSRange(rest.startIndex..., in: rest)),
           let contentRange = Range(openMatch.range(at: 2), in: rest) {
            let prefixRange = Range(openMatch.range, in: rest)!
            body.append(String(rest[..<prefixRange.lowerBound]))
            let pendingContent = String(rest[contentRange])
            if streaming {
                return ParsedThinking(segments: segments, pending: pendingContent, body: body)
            } else {
                body.append(String(rest[prefixRange.lowerBound...]))
                return ParsedThinking(segments: segments, pending: nil, body: body)
            }
        }

        body.append(rest)
        return ParsedThinking(segments: segments, pending: nil, body: body)
    }

    // MARK: - Body parsing (text + tool result JSON)

    private static func parseBodyBlocks(from body: String, codeBlocks: [String]) -> [ContentBlock] {
        // body 已经是 masked 文本；用传入的 codeBlocks 恢复被保护的代码块。
        let masked = body

        var blocks: [ContentBlock] = []
        var currentIndex = masked.startIndex

        while currentIndex < masked.endIndex {
            guard let jsonStart = masked[currentIndex...].firstIndex(where: { $0 == "{" }) else {
                break
            }

            let before = String(masked[currentIndex..<jsonStart])
            let restoredBefore = restoreCodeBlocks(before, blocks: codeBlocks)
            if !restoredBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(restoredBefore.trimmingCharacters(in: .whitespacesAndNewlines)))
            }

            if let (jsonString, jsonEnd) = extractBalancedJSON(from: masked, start: jsonStart),
               let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               looksLikeToolResult(json) {
                let (observation, fileChanges) = parseToolResultJSON(json, raw: jsonString)
                blocks.append(.observation(observation))
                blocks.append(contentsOf: fileChanges.map { .fileChange($0) })
                currentIndex = jsonEnd
            } else {
                let nextBrace = masked[masked.index(after: jsonStart)...].firstIndex(where: { $0 == "{" })
                let textEnd = nextBrace ?? masked.endIndex
                let plainText = String(masked[jsonStart..<textEnd])
                let restoredPlainText = restoreCodeBlocks(plainText, blocks: codeBlocks)
                if !restoredPlainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.text(restoredPlainText.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                currentIndex = textEnd
            }
        }

        let tail = String(masked[currentIndex...])
        let restoredTail = restoreCodeBlocks(tail, blocks: codeBlocks)
        if !restoredTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(.text(restoredTail.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return mergeAdjacentTextBlocks(blocks)
    }

    private static func extractBalancedJSON(from text: String, start: String.Index) -> (String, String.Index)? {
        var depth = 0
        var inString = false
        var escapeNext = false
        var index = start

        while index < text.endIndex {
            let char = text[index]

            if inString {
                if escapeNext {
                    escapeNext = false
                } else if char == "\\" {
                    escapeNext = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                if char == "\"" {
                    inString = true
                } else if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        let end = text.index(after: index)
                        return (String(text[start..<end]), end)
                    }
                } else if char == "\n" && depth == 0 {
                    // 未匹配到闭合的 {，放弃
                    return nil
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func looksLikeToolResult(_ json: [String: Any]) -> Bool {
        let toolResultKeys: Set<String> = [
            "bytes_written", "dirs_created", "files_modified", "files_created",
            "files_deleted", "resolved_path", "path", "files", "output", "error",
            "exit_code", "stdout", "stderr", "command", "content", "message"
        ]
        let keys = Set(json.keys)
        return !keys.isDisjoint(with: toolResultKeys)
    }

    private static func parseToolResultJSON(_ json: [String: Any], raw: String) -> (ObservationBlock, [FileChangeBlock]) {
        // 工具名：优先取 tool/command 字段，读取文件结果无 tool 字段时显示 "read_file"
        let toolName = (json["tool"] as? String)
            ?? (json["command"] as? String)
            ?? (json["content"] != nil ? "read_file" : "tool")

        // 路径：resolved_path 优先，兼容 path
        let resolvedPath = (json["resolved_path"] as? String)
            ?? (json["path"] as? String)

        // 摘要文本
        var summaryParts: [String] = []
        if let resolved = resolvedPath {
            summaryParts.append("path: \(resolved)")
        }
        if let bytes = json["bytes_written"] {
            summaryParts.append("bytes_written: \(bytes)")
        }
        if let message = json["message"] as? String {
            summaryParts.append(message)
        }
        if let output = json["output"] as? String {
            summaryParts.append(output)
        }
        if let error = json["error"] as? String {
            summaryParts.append("error: \(error)")
        }
        if let content = json["content"] as? String {
            let preview = String(content.prefix(200))
            summaryParts.append("content: \(content.count) bytes\n\(preview)")
        }

        let summary = summaryParts.isEmpty ? raw : summaryParts.joined(separator: "\n")
        let observationId = "obs-\(toolName)-\(raw.hashValue)"
        let observation = ObservationBlock(
            id: observationId,
            toolName: toolName,
            text: summary,
            status: json["error"] != nil ? .failed : .completed
        )

        var fileChanges: [FileChangeBlock] = []

        // 预计算 diff 行数，供没有 per-file 统计时作为兜底
        let diffCounts: (additions: Int, deletions: Int)? = {
            if let diff = json["diff"] as? String {
                return countDiffLines(diff)
            }
            return nil
        }()

        let topAdditions = json["additions"] as? Int
        let topDeletions = json["deletions"] as? Int

        func appendChanges(from values: [Any], operation: FileChangeOperation) {
            for value in values {
                let path: String
                var additions: Int? = topAdditions
                var deletions: Int? = topDeletions
                if let dict = value as? [String: Any] {
                    path = (dict["path"] as? String)
                        ?? (dict["resolved_path"] as? String)
                        ?? ""
                    if let a = dict["additions"] as? Int { additions = a }
                    if let d = dict["deletions"] as? Int { deletions = d }
                } else if let str = value as? String {
                    path = str
                    if fileChanges.isEmpty, let counts = diffCounts {
                        additions = counts.additions
                        deletions = counts.deletions
                    }
                } else {
                    continue
                }
                guard !path.isEmpty else { continue }
                fileChanges.append(.init(
                    id: "fc-result-\(operation.rawValue)-\(path)",
                    path: path,
                    operation: operation,
                    additions: additions,
                    deletions: deletions,
                    newContent: nil
                ))
            }
        }

        if let modified = json["files_modified"] as? [Any], !modified.isEmpty {
            appendChanges(from: modified, operation: .modify)
        }
        if let created = json["files_created"] as? [Any], !created.isEmpty {
            appendChanges(from: created, operation: .add)
        }
        if let deleted = json["files_deleted"] as? [Any], !deleted.isEmpty {
            appendChanges(from: deleted, operation: .delete)
        }
        if let files = json["files"] as? [Any], !files.isEmpty {
            appendChanges(from: files, operation: .modify)
        }

        // 仅当存在写入/修改痕迹时才把 resolved_path 标记为修改，避免 read_file 被误标
        let hasWriteEvidence = json["bytes_written"] != nil
            || json["files_modified"] != nil
            || json["files_created"] != nil
            || json["files_deleted"] != nil
        if let resolved = resolvedPath, fileChanges.isEmpty, hasWriteEvidence {
            fileChanges.append(.init(
                id: "fc-resolved-\(resolved)",
                path: resolved,
                operation: .modify,
                additions: topAdditions ?? diffCounts?.additions,
                deletions: topDeletions ?? diffCounts?.deletions,
                newContent: nil
            ))
        }

        return (observation, fileChanges)
    }

    /// 统计 unified diff 中新增/删除的行数（跳过 +++ / --- 文件头）。
    private static func countDiffLines(_ diff: String) -> (additions: Int, deletions: Int) {
        var additions = 0
        var deletions = 0
        for line in diff.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }
            if line.hasPrefix("+++") || line.hasPrefix("---") { continue }
            if line.hasPrefix("+") { additions += 1 }
            else if line.hasPrefix("-") { deletions += 1 }
        }
        return (additions, deletions)
    }

    /// 对两段文本按行做 LCS，估算新增/删除行数。
    private static func diffLineCounts(oldText: String, newText: String) -> (additions: Int, deletions: Int) {
        let oldLines = oldText.components(separatedBy: .newlines)
        let newLines = newText.components(separatedBy: .newlines)
        let m = oldLines.count
        let n = newLines.count
        guard m > 0, n > 0 else {
            return (n, m)
        }
        var prev = [Int](repeating: 0, count: n + 1)
        var curr = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            for j in 1...n {
                if oldLines[i - 1] == newLines[j - 1] {
                    curr[j] = prev[j - 1] + 1
                } else {
                    curr[j] = max(curr[j - 1], prev[j])
                }
            }
            swap(&prev, &curr)
        }
        let lcs = prev[n]
        return (additions: n - lcs, deletions: m - lcs)
    }

    /// 在后端没有返回 additions/deletions 时，根据历史消息里的 read_file / write_file 内容补全线数。
    static func fillMissingLineCounts(for messages: inout [ChatMessage]) {
        var fileContents: [String: String] = [:]

        for i in 0..<messages.count {
            var message = messages[i]

            // 从 read_file 工具结果里缓存文件旧内容
            if message.sender == .tool,
               let data = message.text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["content"] != nil {
                let path = (json["resolved_path"] as? String)
                    ?? (json["path"] as? String)
                    ?? ""
                if let content = json["content"] as? String, !path.isEmpty {
                    fileContents[path] = content
                }
            }

            var updatedBlocks = message.contentBlocks
            for (j, block) in updatedBlocks.enumerated() {
                guard case .fileChange(let fc) = block,
                      (fc.additions == nil || fc.deletions == nil) else { continue }

                let computed: (additions: Int, deletions: Int)
                switch fc.operation {
                case .add:
                    computed = (fc.newContent?.components(separatedBy: .newlines).count ?? 0, 0)
                case .delete:
                    computed = (0, fileContents[fc.path]?.components(separatedBy: .newlines).count ?? 0)
                case .modify:
                    let oldText = fileContents[fc.path] ?? ""
                    let newText = fc.newContent ?? ""
                    computed = diffLineCounts(oldText: oldText, newText: newText)
                }

                updatedBlocks[j] = .fileChange(FileChangeBlock(
                    id: fc.id,
                    path: fc.path,
                    operation: fc.operation,
                    additions: fc.additions ?? computed.additions,
                    deletions: fc.deletions ?? computed.deletions,
                    newContent: fc.newContent
                ))
            }
            message.contentBlocks = updatedBlocks
            messages[i] = message
        }
    }

    private static func mergeAdjacentTextBlocks(_ blocks: [ContentBlock]) -> [ContentBlock] {
        var result: [ContentBlock] = []
        for block in blocks {
            if case .text(let text) = block {
                if let last = result.last, case .text(let lastText) = last {
                    result[result.count - 1] = .text(lastText + "\n\n" + text)
                } else {
                    result.append(block)
                }
            } else {
                result.append(block)
            }
        }
        return result
    }

    // MARK: - Code block protection

    private struct ProtectedText {
        let masked: String
        let blocks: [String]
    }

    private static func protectCodeBlocks(_ text: String) -> ProtectedText {
        var blocks: [String] = []
        var masked = text

        // Fenced code blocks
        let fencePattern = "(^|\\n)( {0,3})(`{3,}|~{3,})[^\\n]*\\n[\\s\\S]*?\\n\\2\\3[ \\t]*(?=\\n|$)"
        if let fenceRegex = try? NSRegularExpression(pattern: fencePattern, options: []) {
            masked = replaceMatches(in: masked, regex: fenceRegex) { matchText in
                blocks.append(matchText)
                return placeholder(at: blocks.count - 1)
            }
        }

        // Inline code
        let inlinePattern = "`[^`\\n]*`"
        if let inlineRegex = try? NSRegularExpression(pattern: inlinePattern, options: []) {
            masked = replaceMatches(in: masked, regex: inlineRegex) { matchText in
                blocks.append(matchText)
                return placeholder(at: blocks.count - 1)
            }
        }

        return ProtectedText(masked: masked, blocks: blocks)
    }

    private static func replaceMatches(
        in text: String,
        regex: NSRegularExpression,
        replacement: (String) -> String
    ) -> String {
        var result = text
        let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let matchText = String(result[range])
            result.replaceSubrange(range, with: replacement(matchText))
        }
        return result
    }

    private static func placeholder(at index: Int) -> String {
        return "⟨THKCODE\(index)⟩"
    }

    private static func restoreCodeBlocks(_ text: String, blocks: [String]) -> String {
        var result = text
        let placeholderPattern = "⟨THKCODE(\\d+)⟩"
        guard let regex = try? NSRegularExpression(pattern: placeholderPattern, options: []) else {
            return result
        }

        var didReplace: Bool
        repeat {
            didReplace = false
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let idxRange = Range(match.range(at: 1), in: result),
                      let idx = Int(result[idxRange]),
                      idx < blocks.count else { continue }
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: blocks[idx])
                didReplace = true
            }
        } while didReplace

        return result
    }

    // MARK: - File change helpers

    private static func stringArgument(from arguments: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = arguments[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func fileChangesFromShellCommand(_ command: String) -> [FileChangeBlock] {
        var changes: [FileChangeBlock] = []
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // rm → delete
        if let regex = try? NSRegularExpression(pattern: "\\brm\\s+-[rf]*\\s*([^;|&<>]+)", options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
           let pathRange = Range(match.range(at: 1), in: trimmed) {
            for path in paths(from: String(trimmed[pathRange])) {
                changes.append(.init(id: "fc-shell-rm-\(path)", path: path, operation: .delete, additions: nil, deletions: nil, newContent: nil))
            }
        }

        // touch → add
        if let regex = try? NSRegularExpression(pattern: "\\btouch\\s+([^;|&<>]+)", options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
           let pathRange = Range(match.range(at: 1), in: trimmed) {
            for path in paths(from: String(trimmed[pathRange])) {
                changes.append(.init(id: "fc-shell-touch-\(path)", path: path, operation: .add, additions: nil, deletions: nil, newContent: nil))
            }
        }

        // cp / mv → modify（目标路径）
        if let regex = try? NSRegularExpression(pattern: "\\b(cp|mv)\\s+([^;|&<>]+)", options: []),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
           let argsRange = Range(match.range(at: 2), in: trimmed) {
            let args = paths(from: String(trimmed[argsRange]))
            if let last = args.last {
                changes.append(.init(id: "fc-shell-cpmv-\(last)", path: last, operation: .modify, additions: nil, deletions: nil, newContent: nil))
            }
        }

        return changes
    }

    private static func paths(from argumentString: String) -> [String] {
        return argumentString
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
    }
}
