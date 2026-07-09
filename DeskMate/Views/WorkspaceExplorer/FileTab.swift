import Foundation

/// 文件选项卡模式。
enum FileTabMode: Equatable {
    /// 普通代码编辑。
    case edit
    /// Diff 审查。
    case diff
}

/// 工作区中已打开的单个文件选项卡。
///
/// 作为代码编辑器内容的"宿主":文件正文、未保存标记、关联 URL 都集中在此。
/// `id` 与 `url` 一并参与 SwiftUI 的视图身份识别 —— 切换 Tab 时,
/// 依靠 `.id(tab.id)` 强制编辑器重建,以便重置光标、滚动位置与撤销栈。
struct FileTab: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var content: String
    /// 文件打开时的磁盘内容，作为无 Git  diff 的基线。
    var baselineContent: String
    var isDirty: Bool
    var mode: FileTabMode

    init(
        url: URL,
        content: String = "",
        baselineContent: String = "",
        isDirty: Bool = false,
        mode: FileTabMode = .edit
    ) {
        self.id = UUID()
        self.url = url
        self.content = content
        self.baselineContent = baselineContent
        self.isDirty = isDirty
        self.mode = mode
    }

    var displayName: String {
        switch mode {
        case .edit:
            return url.lastPathComponent
        case .diff:
            return url.lastPathComponent + " (Diff)"
        }
    }

    var isDiff: Bool {
        if case .diff = mode { return true }
        return false
    }

    /// 必须比较所有字段 — 只比较 `id` 会让 `@State` 数组误以为内容没变,
    /// 导致 `content` / `isDirty` 写回时 SwiftUI 不刷新,SourceEditor 收不到新内容。
    static func == (lhs: FileTab, rhs: FileTab) -> Bool {
        lhs.id == rhs.id &&
        lhs.url == rhs.url &&
        lhs.content == rhs.content &&
        lhs.baselineContent == rhs.baselineContent &&
        lhs.isDirty == rhs.isDirty &&
        lhs.mode == rhs.mode
    }
}
