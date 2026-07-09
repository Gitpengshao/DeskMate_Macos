import Foundation

/// Diff 审查中的一行类型。
enum DiffLineKind: Equatable {
    /// Hunk 头，例如 `@@ -1,3 +1,4 @@`。
    case hunkHeader
    /// 上下文行：旧版本与新版本同时存在。
    case context
    /// 新增行：仅存在于新版本。
    case added
    /// 删除行：仅存在于旧版本。
    case deleted
    /// `\ No newline at end of file` 标记行。
    case noNewlineAtEnd
}

/// Diff 审查中的单条可视化行。
struct DiffLine: Identifiable, Equatable {
    let id = UUID()
    let kind: DiffLineKind
    /// 行文本内容（不包含 diff 前缀 `+` `-` ` `）。
    let text: String
    /// 在旧版本中的行号；新增行与 hunk 头为 `nil`。
    let oldLineNumber: Int?
    /// 在新版本中的行号；删除行与 hunk 头为 `nil`。
    let newLineNumber: Int?
    /// 所属 hunk 在文件中的索引。
    let hunkIndex: Int
    /// 在所属 hunk 内的行索引（包含 hunk 头）。
    let lineIndexInHunk: Int
}

/// Diff 审查中的一个修改块（hunk）。
struct DiffHunk: Equatable {
    /// 旧版本起始行号（1-based）。
    let oldStart: Int
    /// 旧版本包含行数。
    let oldCount: Int
    /// 新版本起始行号（1-based）。
    let newStart: Int
    /// 新版本包含行数。
    let newCount: Int
    /// Hunk 头原始文本。
    let header: String
    /// Hunk 内所有行（首行通常为 hunkHeader）。
    let lines: [DiffLine]
}

/// 单个文件的 diff 信息。
struct DiffFile: Equatable {
    /// 旧文件路径。
    let oldPath: String
    /// 新文件路径；重命名/复制时可能与 oldPath 不同。
    let newPath: String
    /// 所有 hunk。
    let hunks: [DiffHunk]
    /// 是否为新增文件。
    let isNew: Bool
    /// 是否为删除文件。
    let isDeleted: Bool
    /// 是否为二进制文件。
    let isBinary: Bool

    /// 用于展示的文件路径。
    var displayPath: String { newPath.isEmpty ? oldPath : newPath }
}

/// 一次完整的 diff 审查数据。
struct GitDiff: Equatable {
    let files: [DiffFile]
}

// MARK: - Diff 数据来源

/// DiffReviewView 的数据来源。
enum DiffSource: Equatable {
    /// 从 Git 仓库获取 base 与 diff。
    case git(workingDirectory: String)
    /// 从本地基线与当前内容直接生成 diff。
    ///
    /// - `baseContent`: 基线内容（如文件打开时的磁盘内容）。
    /// - `proposedContent`: 当前内容（可能包含未保存的编辑器修改）。
    /// - `isNew`: 是否为新增文件（base 为空）。
    case local(baseContent: String, proposedContent: String, isNew: Bool)
}

// MARK: - 接受 / 拒绝动作

/// 对 diff 某一层级（整文件 / hunk / 单行）的显式决定。
enum DiffAction: Equatable {
    /// 未做显式决定，按上层默认推导。
    case `default`
    /// 接受该变更。
    case accepted
    /// 拒绝该变更。
    case rejected
}

extension DiffAction {
    /// 返回有效动作；`default` 视作 `accepted`（工作区 diff 默认保留当前修改）。
    var effective: DiffAction {
        self == .default ? .accepted : self
    }

    /// 切换动作：default/accepted → rejected，rejected → accepted。
    mutating func toggle() {
        switch effective {
        case .accepted: self = .rejected
        case .rejected: self = .accepted
        default: self = .rejected
        }
    }
}

/// 唯一标识一行在 diff 中的位置，用于存储显式行级决定。
struct DiffLineKey: Hashable, Equatable {
    let hunkIndex: Int
    let lineIndexInHunk: Int
}
