import Foundation

/// 不依赖 Git 的文本 diff 工具：对两行文本做行级 Myers diff，输出 unified diff 文本。
///
/// 输出格式与 `git diff -U<contextLines>` 一致，可直接交给 `DiffParser.parse` 解析。
enum TextDiffer {

    /// 计算 `old` 与 `new` 的 unified diff。
    ///
    /// - Parameters:
    ///   - old: 基线内容。
    ///   - new: 当前内容。
    ///   - path: 文件路径（仅用于 diff 头）。
    ///   - contextLines: hunk 上下文行数。
    /// - Returns: unified diff 文本；若两者完全一致则返回空字符串。
    static func unifiedDiff(
        old: String,
        new: String,
        path: String,
        contextLines: Int = 3
    ) -> String {
        let oldLines = old.isEmpty ? [] : LineEnding.splitLines(old)
        let newLines = new.isEmpty ? [] : LineEnding.splitLines(new)

        DMLogger.log("TextDiffer.unifiedDiff: oldLines=\(oldLines.count), newLines=\(newLines.count), equal=\(oldLines == newLines), path=\(path)", name: "DiffDebug")

        if oldLines == newLines {
            return ""
        }

        let ops = myersDiff(old: oldLines, new: newLines)
        DMLogger.log("TextDiffer.unifiedDiff: ops=\(ops.count)", name: "DiffDebug")
        guard !ops.isEmpty else { return "" }

        var output = ""
        output.append("diff --git a/\(path) b/\(path)\n")
        output.append("--- a/\(path)\n")
        output.append("+++ b/\(path)\n")

        let hunks = buildHunks(ops: ops, contextLines: max(0, contextLines))
        for hunk in hunks {
            output.append(hunk.header)
            output.append("\n")
            for line in hunk.lines {
                switch line.kind {
                case .equal:
                    output.append(" \(line.text)\n")
                case .delete:
                    output.append("-\(line.text)\n")
                case .insert:
                    output.append("+\(line.text)\n")
                }
            }
        }

        return output
    }

    // MARK: - Myers diff

    private enum EditOp {
        case equal
        case delete
        case insert
    }

    private struct Hunk {
        let header: String
        let lines: [(kind: EditOp, text: String)]
    }

    /// Myers O((N+M)D) 最短编辑脚本。
    private static func myersDiff(old: [String], new: [String]) -> [(kind: EditOp, text: String)] {
        let n = old.count
        let m = new.count

        // 边界：全新增或全删除
        if n == 0 {
            return new.map { (kind: .insert, text: $0) }
        }
        if m == 0 {
            return old.map { (kind: .delete, text: $0) }
        }

        let maxD = n + m
        var v = Array(repeating: 0, count: 2 * maxD + 1)
        var trace: [[Int]] = []

        outer: for d in 0...maxD {
            trace.append(v)
            for k in stride(from: -d, through: d, by: 2) {
                let index = k + maxD
                var x: Int
                if k == -d || (k != d && v[index - 1] < v[index + 1]) {
                    x = v[index + 1]
                } else {
                    x = v[index - 1] + 1
                }
                var y = x - k

                while x < n && y < m && old[x] == new[y] {
                    x += 1
                    y += 1
                }

                v[index] = x

                if x >= n && y >= m {
                    // 找到最短路径，开始回溯
                    return backtrack(old: old, new: new, trace: trace, d: d, maxD: maxD)
                }
            }
        }

        return []
    }

    private static func backtrack(
        old: [String],
        new: [String],
        trace: [[Int]],
        d: Int,
        maxD: Int
    ) -> [(kind: EditOp, text: String)] {
        var ops: [(kind: EditOp, text: String)] = []
        var x = old.count
        var y = new.count

        for currentD in stride(from: d, through: 1, by: -1) {
            let k = x - y
            let index = k + maxD
            let prevV = trace[currentD]

            let prevK: Int
            let prevX: Int
            if k == -currentD || (k != currentD && prevV[index - 1] < prevV[index + 1]) {
                prevK = k + 1
                prevX = prevV[prevK + maxD]
            } else {
                prevK = k - 1
                prevX = prevV[prevK + maxD]
            }
            let prevY = prevX - prevK

            // 判断当前步是非对角线移动：insert（来自 k+1）或 delete（来自 k-1）。
            let isInsert = prevK == k + 1
            let moveX = isInsert ? prevX : prevX + 1
            let moveY = isInsert ? prevY + 1 : prevY

            // 记录当前步之后的对角线移动（equal）。
            var diagX = moveX
            var diagY = moveY
            while diagX < x && diagY < y {
                ops.append((kind: .equal, text: old[diagX]))
                diagX += 1
                diagY += 1
            }

            // 记录当前步的非对角线移动（insert / delete）。
            if isInsert {
                ops.append((kind: .insert, text: new[prevY]))
            } else {
                ops.append((kind: .delete, text: old[prevX]))
            }

            x = prevX
            y = prevY
        }

        // 从 (0,0) 到当前 (x,y) 的剩余对角线
        var diagX = 0
        var diagY = 0
        while diagX < x && diagY < y {
            ops.append((kind: .equal, text: old[diagX]))
            diagX += 1
            diagY += 1
        }

        ops.reverse()
        return ops
    }

    // MARK: - 行级变更标记

    /// 当前内容相对基线的行级变更标记（用于编辑器 gutter）。
    struct LineDiffMarker: Equatable {
        let newLineNumber: Int  // 0-based，在当前内容中的行号
        let kind: LineDiffMarkerKind
    }

    enum LineDiffMarkerKind: Equatable {
        case added
        case modified
        case deleted

        /// 去重优先级：数值越高越优先显示。
        var priority: Int {
            switch self {
            case .added: return 1
            case .deleted: return 2
            case .modified: return 3
            }
        }
    }

    /// 计算当前内容相对基线的行级变更标记。
    ///
    /// - 新增行：绿色标记。
    /// - 删除行：红色标记（标记在删除位置之后的行号）。
    /// - 修改行：相邻的 delete + insert 识别为黄色标记。
    static func lineMarkers(old: String, new: String) -> [LineDiffMarker] {
        let oldLines = old.isEmpty ? [] : LineEnding.splitLines(old)
        let newLines = new.isEmpty ? [] : LineEnding.splitLines(new)

        if oldLines == newLines {
            return []
        }

        let ops = myersDiff(old: oldLines, new: newLines)
        var markers: [LineDiffMarker] = []
        var newLine = 0

        var i = 0
        while i < ops.count {
            switch ops[i].kind {
            case .equal:
                newLine += 1
                i += 1
            case .delete:
                // 若 delete 后紧跟 insert，视为修改（黄色）。
                if i + 1 < ops.count && ops[i + 1].kind == .insert {
                    markers.append(LineDiffMarker(newLineNumber: newLine, kind: .modified))
                    newLine += 1
                    i += 2
                } else {
                    // 纯删除：在删除位置后的行号上显示红色标记。
                    let deletionLine = max(0, newLine)
                    markers.append(LineDiffMarker(newLineNumber: deletionLine, kind: .deleted))
                    i += 1
                }
            case .insert:
                markers.append(LineDiffMarker(newLineNumber: newLine, kind: .added))
                newLine += 1
                i += 1
            }
        }

        // 同一行可能出现多个标记，按优先级去重：modified > deleted > added。
        var byLine: [Int: LineDiffMarkerKind] = [:]
        for marker in markers {
            if let existing = byLine[marker.newLineNumber] {
                if marker.kind.priority > existing.priority {
                    byLine[marker.newLineNumber] = marker.kind
                }
            } else {
                byLine[marker.newLineNumber] = marker.kind
            }
        }

        return byLine
            .map { LineDiffMarker(newLineNumber: $0.key, kind: $0.value) }
            .sorted { $0.newLineNumber < $1.newLineNumber }
    }

    // MARK: - Hunk 分组

    private static func buildHunks(
        ops: [(kind: EditOp, text: String)],
        contextLines: Int
    ) -> [Hunk] {
        // 1. 找出所有变更区域的索引范围（0-based），并向外扩展上下文。
        var regions: [ClosedRange<Int>] = []
        var i = 0
        while i < ops.count {
            if ops[i].kind == .equal {
                i += 1
                continue
            }
            let start = i
            while i < ops.count && ops[i].kind != .equal {
                i += 1
            }
            let end = i - 1
            let expandedStart = max(0, start - contextLines)
            let expandedEnd = min(ops.count - 1, end + contextLines)
            regions.append(expandedStart...expandedEnd)
        }

        guard !regions.isEmpty else { return [] }

        // 2. 合并重叠或相邻的区域。
        var merged: [ClosedRange<Int>] = []
        for region in regions {
            if let last = merged.last, region.lowerBound <= last.upperBound + 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, region.upperBound)
            } else {
                merged.append(region)
            }
        }

        // 3. 为每个区域生成 hunk。
        var hunks: [Hunk] = []
        for region in merged {
            let hunkOps = Array(ops[region.lowerBound...region.upperBound])

            var oldLine = 0
            var newLine = 0
            // 计算 hunk 开始前 old/new 的当前行号（1-based）
            for op in ops[..<region.lowerBound] {
                switch op.kind {
                case .equal:
                    oldLine += 1
                    newLine += 1
                case .delete:
                    oldLine += 1
                case .insert:
                    newLine += 1
                }
            }

            let oldStart = oldLine + 1
            let newStart = newLine + 1
            var oldCount = 0
            var newCount = 0

            for op in hunkOps {
                switch op.kind {
                case .equal:
                    oldCount += 1
                    newCount += 1
                case .delete:
                    oldCount += 1
                case .insert:
                    newCount += 1
                }
            }

            let oldHeader = oldCount == 0 ? "\(oldStart - 1),0" : oldCount == 1 ? "\(oldStart)" : "\(oldStart),\(oldCount)"
            let newHeader = newCount == 0 ? "\(newStart - 1),0" : newCount == 1 ? "\(newStart)" : "\(newStart),\(newCount)"
            let header = "@@ -\(oldHeader) +\(newHeader) @@"

            hunks.append(Hunk(header: header, lines: hunkOps))
        }

        return hunks
    }
}
