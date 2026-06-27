import SwiftUI

/// 任务看板页统一使用的黑白主题色板。
///
/// 严格对齐 Flutter 端灰阶（来自 `task_board_page.dart`）：
/// - `0xFF1A1A1A` — 页面背景
/// - `0xFF141414` — 卡片内层 / 弹窗
/// - `0xFF2E2E2E` — 边框
/// - `0xFFE5E5E5` — 浅色模式边框
/// - `0xFFFAFAFA` / `0xFF171717` — 主文本
/// - `0xFF737373` — 弱化文本
/// - `0xFFF0F0F0` / `0xFFF5F5F5` — 浅色模式 chip 背景
/// - 状态色：`0xFF22C55E` 完成 / `0xFF3B82F6` 开始 / `0xFFF59E0B` 阻塞 / `0xFFEF4444` 删除
enum TBPalette {

    // ---- Surfaces ----
    static let bgBase     = Color(red: 0.102, green: 0.102, blue: 0.102)  // #1A1A1A
    static let cardBg     = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let cardBgAlt  = Color(red: 0.102, green: 0.102, blue: 0.102)  // #1A1A1A
    static let bgElevated = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let inputBg    = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let columnBg   = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let countBg    = Color(red: 0.141, green: 0.141, blue: 0.141)  // #242424

    // ---- Borders ----
    static let border        = Color(red: 0.180, green: 0.180, blue: 0.180)  // #2E2E2E
    static let borderSubtle  = Color(red: 0.180, green: 0.180, blue: 0.180)  // #2E2E2E
    static let divider       = Color(red: 0.149, green: 0.149, blue: 0.149)  // #262626

    // ---- Text ----
    static let textPrimary  = Color(red: 0.980, green: 0.980, blue: 0.980)  // #FAFAFA
    static let textInk      = Color(red: 0.090, green: 0.090, blue: 0.090)  // #171717
    static let textMuted    = Color(red: 0.450, green: 0.450, blue: 0.450)  // #737373
    static let textDisabled = Color(red: 0.640, green: 0.640, blue: 0.640)  // #A3A3A3
    static let textHeader   = Color(red: 0.640, green: 0.640, blue: 0.640)  // #A3A3A3

    // ---- Inverse (active highlight) ----
    static let inverse    = Color(red: 0.980, green: 0.980, blue: 0.980)  // #FAFAFA
    static let inverseInk = Color(red: 0.039, green: 0.039, blue: 0.039)  // #0A0A0A

    // ---- Status (保留少量状态色，与 Flutter 端 detail popup 一致) ----
    static let statusComplete  = Color(red: 0.133, green: 0.773, blue: 0.369)  // #22C55E
    static let statusStart     = Color(red: 0.231, green: 0.510, blue: 0.965)  // #3B82F6
    static let statusBlock     = Color(red: 0.961, green: 0.620, blue: 0.043)  // #F59E0B
    static let statusDanger    = Color(red: 0.937, green: 0.267, blue: 0.267)  // #EF4444
}

// MARK: - Text copy

/// 任务看板页硬编码文案（与 Flutter 端 `app_localizations` 的中文保持一致）。
enum TBText {
    // Header
    static let pageTitle       = "任务看板"
    static let pageSubtitle    = "管理 Hermes 看板任务，从 Triage 到 Done 全流程跟踪"
    static let currentBoard    = "当前看板: "

    // Buttons
    static let switchBoard     = "切换看板"
    static let newTask         = "新建任务"
    static let refresh         = "刷新"
    static let nudge           = "Nudge"
    static let newBoard        = "新建看板"

    // Columns
    static let columnTriage    = "Triage"
    static let columnTodo      = "To Do"
    static let columnReady     = "Ready"
    static let columnInProgress = "Running"
    static let columnBlocked   = "Blocked"
    static let columnDone      = "Done"

    // Triage / dispatch actions
    static let decompose       = "分解"
    static let specify         = "Specify"

    // Detail popup
    static let parentTasks     = "父任务"
    static let childTasks      = "子任务"
    static let runHistory      = "运行历史"
    static let addComment      = "添加"

    // Boards section
    static let boardList       = "看板列表"

    // Form labels
    static let taskTitle       = "标题"
    static let taskBody        = "描述"
    static let assignee        = "Assignee"
    static let priority        = "优先级"
    static let status          = "状态"
    static let workspace       = "Workspace"
    static let branch          = "Branch"
    static let tenant          = "Tenant"
    static let skills          = "技能"
    static let maxRetries      = "最大重试次数"
    static let selectDirectory = "选择目录…"
    static let create          = "创建"
    static let cancel          = "取消"
    static let close           = "关闭"

    // States
    static let loading         = "加载看板中…"
    static let empty           = "暂无任务"
    static let unassigned      = "未分配"
    static let required        = " *"

    // Detail popup actions
    static let completeAction  = "完成"
    static let blockAction     = "阻塞"
    static let unblockAction   = "解除阻塞"
    // Hermes Kanban 不支持硬删除,deleteTask 实际走 archive —— 文案对齐官方语义。
    static let deleteAction    = "归档"

    // Detail popup
    static let statusLabel     = "状态"
    static let priorityLabel   = "优先级"
    static let assigneeLabel   = "负责人"
    static let commentsLabel   = "评论"

    // Errors
    static let gatewayUnreachable = "无法连接到 Hermes Gateway，请确认 Gateway 已启动。"

    // Helpers
    static func currentBoardName(_ name: String) -> String {
        if name.isEmpty { return currentBoard + "—" }
        return currentBoard + name
    }

    static func boardChip(_ name: String, _ count: String) -> String {
        return "\(name) · \(count)"
    }
}
