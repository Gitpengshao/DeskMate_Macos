import SwiftUI

/// 技能管理页统一使用的黑白主题色板。
///
/// 严格对齐 Flutter 端灰阶：
/// - `0xFF1A1A1A` — 页面背景
/// - `0xFF1E1E1E` / `0xFF2E2E2E` — 卡片背景 / 边框
/// - `0xFFFAFAFA` / `0xFF171717` — 主文本
/// - `0xFF737373` — 弱化文本
/// - `0xFFA3A3A3` / `0xFF525252` — 分类标题
/// - `0xFF16A34A` — Installed 状态
enum SMPalette {
    // ---- Surfaces ----
    static let bgBase     = Color(red: 0.102, green: 0.102, blue: 0.102)  // #1A1A1A
    static let cardBg     = Color(red: 0.118, green: 0.118, blue: 0.118)  // #1E1E1E
    static let bgElevated = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let bgHover    = Color(red: 0.110, green: 0.110, blue: 0.110)  // #1A1A1A

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

    // ---- Inverse (used for active highlight) ----
    static let inverse    = Color(red: 0.980, green: 0.980, blue: 0.980)  // #FAFAFA
    static let inverseInk = Color(red: 0.039, green: 0.039, blue: 0.039)  // #0A0A0A

    // ---- Status (保留少量状态色) ----
    static let statusInstalled     = Color(red: 0.086, green: 0.639, blue: 0.290)  // #16A34A
    static let statusInstalledBg   = Color(red: 0.086, green: 0.639, blue: 0.290).opacity(0.15)
}

// MARK: - Text copy

/// 技能管理页硬编码文案（与 Flutter 端 `app_localizations` 的中文保持一致）。
enum SMText {
    // Header
    static let pageTitle        = "技能管理"
    static let pageSubtitle     = "管理 Hermes 内置技能与可选技能"
    static let browseRegistry   = "浏览技能市场"

    // Tabs
    static let tabBuiltIn     = "内置技能"
    static let tabAvailable   = "可用技能"

    // Counts / footer
    static func installedCount(_ count: Int) -> String {
        return "已安装 \(count)"
    }
    static func skillsPath(_ path: String) -> String {
        return "~/.hermes/skills/\(path)"
    }

    // States
    static let loading        = "加载技能中..."
    static let emptyBuiltIn   = "暂无内置技能"
    static let emptyAvailable = "暂无可用技能"

    // Actions
    static let actionRestore   = "Restore"
    static let actionUninstall = "Uninstall"
    static let actionInstall   = "Install"

    // Status badge
    static let badgeInstalled = "Installed"
}
