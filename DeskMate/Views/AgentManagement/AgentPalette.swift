import SwiftUI

/// 多智能体（profile）页面统一使用的黑白主题色板。
///
/// 严格对齐 Flutter 端灰阶（与 SkillManagement / TaskBoard / ModelConfig 一致）：
/// - `0xFF1A1A1A` — 页面背景
/// - `0xFF141414` — 卡片内层 / 弹窗
/// - `0xFF1E1E1E` — 卡片背景
/// - `0xFF2E2E2E` — 边框
/// - `0xFFFAFAFA` / `0xFF171717` — 主文本
/// - `0xFF737373` — 弱化文本
/// - `0xFF22C55E` — 运行中状态
/// - `0xFF6B6B6B` — 已停止状态
enum AgentPalette {
    // ---- Surfaces ----
    static let bgBase     = Color(red: 0.102, green: 0.102, blue: 0.102)  // #1A1A1A
    static let cardBg     = Color(red: 0.118, green: 0.118, blue: 0.118)  // #1E1E1E
    static let bgElevated = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let bgPanel    = Color(red: 0.094, green: 0.094, blue: 0.094)  // #181818
    static let bgHover    = Color(red: 0.110, green: 0.110, blue: 0.110)  // #1C1C1C
    static let sidePanel  = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414

    // ---- Borders ----
    static let border        = Color(red: 0.180, green: 0.180, blue: 0.180)  // #2E2E2E
    static let borderSubtle  = Color(red: 0.149, green: 0.149, blue: 0.149)  // #262626
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

    // ---- Status (保留少量状态色) ----
    static let statusRunning    = Color(red: 0.133, green: 0.773, blue: 0.369)  // #22C55E
    static let statusStopped    = Color(red: 0.420, green: 0.420, blue: 0.420)  // #6B6B6B
    static let statusDistribution = Color(red: 0.231, green: 0.510, blue: 0.965)  // #3B82F6
}

// MARK: - Text copy

/// 多智能体页面硬编码文案（与 Flutter 端 `app_localizations` 的中文保持一致）。
enum AgentText {

    // ---- Header ----
    static let pageTitle       = "多智能体协同"
    static let pageSubtitle    = "管理多个独立的 Hermes profile — 每个 profile 拥有各自的配置、记忆、会话、技能和 gateway"
    static let currentActive   = "当前激活"

    // ---- Toolbar ----
    static let newProfile      = "新建 profile"
    static let refresh         = "刷新"

    // ---- Side Panel (left) ----
    static let search          = "搜索 profile"
    static let totalCount      = "共 %d 个"

    static let fieldId         = "ID"
    static let fieldName       = "名称"
    static let fieldModel      = "模型"
    static let fieldProvider   = "Provider"
    static let fieldDescription = "描述"
    static let fieldProfileName = "profile 名"
    static let fieldCloneFrom  = "源 profile"
    static let fieldDescriptionHint = "描述（Kanban 编排器根据此描述路由任务，可选）"

    // ---- Buttons ----
    static let renameProfile   = "重命名"
    static let deleteProfile   = "删除"
    static let editDescription = "编辑描述"
    static let editModel       = "编辑模型"
    static let editSoul        = "编辑 SOUL.md"
    static let editSkills      = "编辑技能"
    static let save            = "保存"
    static let cancel          = "取消"
    static let confirm         = "确认"
    static let create          = "创建"
    static let close           = "关闭"
    static let openInFinder    = "在 Finder 中显示"

    // ---- Dialogs ----
    static let newProfileTitle = "新建 profile"
    static let cloneProfileTitle = "克隆 profile"
    static let renameTitle     = "重命名 profile"
    static let deleteTitle     = "删除 profile"
    static let modelTitle      = "编辑主模型"
    static let soulTitle       = "编辑 SOUL.md"
    static let skillsTitle     = "编辑技能"

    // ---- Helpers ----
    static func notEmpty(_ s: String, fallback: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : s
    }

    // ---- Empty / Errors ----
    static let emptyTitle      = "还没有 profile"
    static let emptyHint       = "点击「新建 profile」创建你的第一个智能体"
    static let loadingTitle    = "加载 profile 中..."
    static let defaultProfileHint = "默认 profile 不可删除"

    // ---- Empty / Validation ----
    static let invalidName     = "profile 名必须为小写字母数字 + 连字符 / 下划线，且以字母数字开头"
    static let noCloneFrom     = "克隆模式需要指定源 profile"
}
