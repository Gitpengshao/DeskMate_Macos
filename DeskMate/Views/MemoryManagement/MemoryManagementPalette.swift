import SwiftUI

/// 记忆管理页统一使用的黑白主题色板。
/// 色彩严格对齐 Flutter 端 `0xFFFAFAFA` / `0xFF171717` / `0xFF2E2E2E` 等灰阶。
enum MMPalette {
    // ---- Surfaces ----
    static let bgBase     = Color(red: 0.000, green: 0.000, blue: 0.000)  // #000000
    static let bgPanel    = Color(red: 0.039, green: 0.039, blue: 0.039)  // #0A0A0A
    static let bgElevated = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let bgHover    = Color(red: 0.102, green: 0.102, blue: 0.102)  // #1A1A1A
    static let bgInput    = Color(red: 0.039, green: 0.039, blue: 0.039)  // #0A0A0A

    // ---- Borders ----
    static let border     = Color(red: 0.180, green: 0.180, blue: 0.180)  // #2E2E2E
    static let borderSoft = Color(red: 0.149, green: 0.149, blue: 0.149)  // #262626

    // ---- Text ----
    static let textPrimary   = Color(red: 0.980, green: 0.980, blue: 0.980)  // #FAFAFA
    static let textSecondary = Color(red: 0.090, green: 0.090, blue: 0.090)  // #171717
    static let textTertiary  = Color(red: 0.640, green: 0.640, blue: 0.640)  // #A3A3A3
    static let textMuted     = Color(red: 0.450, green: 0.450, blue: 0.450)  // #737373

    // ---- Inverse (used for active highlight) ----
    static let inverse    = Color(red: 0.980, green: 0.980, blue: 0.980)  // #FAFAFA
    static let inverseInk = Color(red: 0.000, green: 0.000, blue: 0.000)  // #000000

    // ---- Status (保留少量状态色) ----
    static let statusRunning    = Color(red: 0.133, green: 0.773, blue: 0.369)  // #22C55E
    static let statusInstalling = Color(red: 0.961, green: 0.620, blue: 0.043)  // #F59E0B
    static let statusError      = Color(red: 0.937, green: 0.267, blue: 0.267)  // #EF4444
    static let statusErrorBg    = Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.2)
}

// MARK: - Text copy

/// 记忆管理页硬编码文案（与 Flutter 端 `app_localizations` 的中文保持一致）。
enum MMText {
    // Tabs
    static let tabMemory      = "记忆"
    static let tabUserProfile = "用户画像"
    static let tabProviders   = "Provider"

    // Capacity
    static func capacity(used: String, total: String, entries: String) -> String {
        return "\(used) / \(total) 字符 · \(entries) 条"
    }

    // Actions
    static let addEntry  = "新增条目"
    static let cancel    = "取消"
    static let confirm   = "确定"
    static let delete    = "删除"
    static let editEntry = "编辑条目"
    static let newPersona = "新建用户画像"

    // Placeholders
    static let addPlaceholder = "例如：- 使用 § 分隔条目\n- 每条记忆独立成段"

    // States
    static let loadingMemories  = "加载记忆中..."
    static let loadingPersonas  = "加载用户画像..."
    static let emptyMemory      = "暂无记忆条目"
    static let emptyPersona     = "暂无用户画像"

    // Delete dialog
    static let deletePersonaTitle   = "删除该条目？"
    static func deletePersonaConfirm(_ preview: String) -> String {
        return "将永久删除：\(preview)"
    }

    // Provider card
    static let providersHeader        = "外部记忆 Provider"
    static let providerBestFor        = "适用场景"
    static let providerRequires       = "依赖"
    static let providerStorage        = "数据存储"
    static let providerCost           = "费用"
    static let providerPython         = "Python"
    static let providerPythonNone     = "未找到可用 Python 解释器"
    static let providerPythonChange   = "选择解释器"
    static let providerPythonRescan   = "重新检测"

    static let providerRunning    = "运行中"
    static let providerInstalling = "安装中"
    static let providerError      = "错误"
    static let providerStopped    = "已停止"
    static let providerDisabled   = "未启用"

    // Python picker
    static let pythonPickerTitle         = "选择 Python 解释器"
    static let pythonPickerSubtitle      = "OpenViking 需要通过 pip 安装，请选择一个能访问 PyPI 的 Python 3.10+ 解释器。"
    static let pythonPickerEmpty         = "未扫描到任何 Python 解释器，请确认已安装 Python 3.10+"
    static let pythonPickerScanning      = "正在扫描..."
    static let pythonPickerClear         = "清除手动选择"
    static let pythonPickerCurrent       = "当前"
    static let pythonPickerSystem        = "系统"
    static let pythonPickerClose         = "关闭"

    // Errors
    static let errorBannerTitle = "操作失败"
}
