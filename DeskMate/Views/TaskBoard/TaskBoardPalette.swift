import SwiftUI

/// 任务看板页统一使用的黑白主题色板。
enum TBPalette {

    // ---- Surfaces ----
    static let bgBase     = Color(red: 0.102, green: 0.102, blue: 0.102)  // #1A1A1A
    static let cardBg     = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let cardBgAlt  = Color(red: 0.102, green: 0.102, blue: 0.102)  // #1A1A1A
    static let bgElevated = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let inputBg    = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414

    // ---- Borders ----
    static let border        = Color(red: 0.180, green: 0.180, blue: 0.180)  // #2E2E2E
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

    // ---- Status ----
    static let statusComplete  = Color(red: 0.133, green: 0.773, blue: 0.369)  // #22C55E
    static let statusStart     = Color(red: 0.231, green: 0.510, blue: 0.965)  // #3B82F6
    static let statusBlock     = Color(red: 0.961, green: 0.620, blue: 0.043)  // #F59E0B
    static let statusDanger    = Color(red: 0.937, green: 0.267, blue: 0.267)  // #EF4444
}

// MARK: - Text copy

/// 任务看板页硬编码文案。
enum TBText {
    // Header
    static let pageTitle       = "任务看板"

    // Buttons
    static let switchBoard     = "切换看板"
    static let newTask         = "新建任务"
    static let refresh         = "刷新"
    static let nudge           = "Nudge"
    static let newBoard        = "新建看板"

    // Form labels
    static let taskTitle       = "标题"
    static let taskBody        = "描述"
    static let assignee        = "Assignee"
    static let priority        = "优先级"
    static let status          = "状态"
    static let workspace       = "Workspace"
    static let create          = "创建"
    static let cancel          = "取消"
    static let close           = "关闭"

    // States
    static let loading         = "加载看板中…"
    static let empty           = "暂无任务"
    static let required        = " *"

    // Detail popup actions
    static let completeAction  = "完成"
    static let blockAction     = "阻塞"
    static let unblockAction   = "解除阻塞"
    // Hermes Kanban 不支持硬删除,deleteTask 实际走 archive。
    static let deleteAction    = "归档"

    // Detail popup
    static let statusLabel     = "状态"
    static let priorityLabel   = "优先级"
    static let assigneeLabel   = "负责人"

    // Errors
    static let gatewayUnreachable = "无法连接到 Hermes Gateway，请确认 Gateway 已启动。"
}
