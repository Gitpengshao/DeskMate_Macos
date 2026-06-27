import Foundation

// MARK: - Memory Tab

/// 记忆管理页的三个 Tab 类型 — 对齐 Flutter `MemoryTab`。
enum MemoryTab: String, Equatable, CaseIterable, Identifiable {
    case memory       // MEMORY.md
    case userProfile  // USER.md
    case providers    // 外部记忆 Provider

    var id: String { rawValue }
}

// MARK: - Memory Provider

/// 外部记忆 Provider 标识 — 对齐 Flutter `MemoryProviderId`。
enum MemoryProviderId: String, Equatable, Codable {
    case openviking
}

/// Provider 运行状态 — 对齐 Flutter `ProviderStatus`。
enum ProviderStatus: String, Equatable {
    case notInstalled
    case installing
    case stopped
    case running
    case error
}

/// 记忆条目所属文件 — 对齐 Flutter `MemoryTarget`。
enum MemoryTarget: String, Equatable, Codable {
    case memory
    case user
}

// MARK: - Memory Entry

/// 一条记忆条目，存放在 `~/.hermes/memories/MEMORY.md` 或 `USER.md`。
///
/// Hermes 使用 `§` 作为段分隔符；每条 entry 可包含多行文本。
struct MemoryEntry: Identifiable, Equatable, Codable {
    /// MEMORY.md（agent notes）或 USER.md（user profile）。
    let target: MemoryTarget
    /// 在文件中的索引，用于定位编辑/删除。
    let index: Int
    /// 条目内容。
    let content: String

    /// 唯一 id，组合 target 与 index。
    var id: String { "\(target.rawValue)_\(index)" }

    init(target: MemoryTarget, index: Int, content: String) {
        self.target = target
        self.index = index
        self.content = content
    }

    /// 仅更新内容（保持 target/index 不变），用于编辑。
    func updatingContent(_ newContent: String) -> MemoryEntry {
        MemoryEntry(target: target, index: index, content: newContent)
    }
}

// MARK: - Memory Provider Info

/// 外部记忆 Provider 的静态描述信息 — 对齐 Flutter `MemoryProviderInfo`。
struct MemoryProviderInfo: Equatable, Identifiable {
    let id: MemoryProviderId
    let name: String
    let description: String
    let bestFor: String
    let requires: String
    let dataStorage: String
    let cost: String
}

/// 内置 Provider 列表 — 对齐 Flutter `builtInProviders`。
let kBuiltInMemoryProviders: [MemoryProviderInfo] = [
    MemoryProviderInfo(
        id: .openviking,
        name: "OpenViking",
        description: "字节跳动开源知识库，支持文件系统式层级浏览、分层检索和6类自动记忆提取。",
        bestFor: "自托管知识管理与结构化浏览",
        requires: "pip install openviking + 启动服务端",
        dataStorage: "自托管 (本地或云端)",
        cost: "免费 (开源，AGPL-3.0)"
    )
]

// MARK: - Page State Model

/// 记忆管理页的单一状态源 — 对齐 Flutter `MemoryManagementModel`。
struct MemoryManagementModel: Equatable {
    var activeTab: MemoryTab

    /// MEMORY.md 条目（agent permanent memory / notes）。
    var memoryEntries: [MemoryEntry]
    /// USER.md 条目（user profile / preferences）。
    var userProfileEntries: [MemoryEntry]

    var isLoadingMemories: Bool
    var isLoadingUserProfile: Bool
    var errorMessage: String?

    // ---- External provider state ----

    /// 当前激活的外部 Provider（nil = 未启用）。
    var activeProvider: MemoryProviderId?
    /// Provider 状态。
    var providerStatus: ProviderStatus
    /// Provider 状态的人类可读消息。
    var providerStatusMessage: String?
    /// 运行中 Provider 的 endpoint URL。
    var providerEndpoint: String?

    // ---- Python interpreter ----

    /// 当前正在使用的 Python 解释器绝对路径。
    var pythonPath: String?
    /// 已发现的 Python 候选列表（用于"更改解释器"UI）。
    var pythonCandidates: [PythonCandidate]
    /// 是否正在扫描候选解释器。
    var isScanningPython: Bool
    /// 是否正在显示"选择 Python 解释器"对话框。
    var isShowingPythonPicker: Bool
    /// pip install 实时输出（最近若干行），用于在状态卡片上显示进度。
    var installProgressLog: String
    /// pip 镜像源 URL。
    var pipIndexUrl: String
    /// 是否正在显示"pip 镜像源"对话框。
    var isShowingPipMirrorEditor: Bool

    init(
        activeTab: MemoryTab = .memory,
        memoryEntries: [MemoryEntry] = [],
        userProfileEntries: [MemoryEntry] = [],
        isLoadingMemories: Bool = false,
        isLoadingUserProfile: Bool = false,
        errorMessage: String? = nil,
        activeProvider: MemoryProviderId? = nil,
        providerStatus: ProviderStatus = .notInstalled,
        providerStatusMessage: String? = nil,
        providerEndpoint: String? = nil,
        pythonPath: String? = nil,
        pythonCandidates: [PythonCandidate] = [],
        isScanningPython: Bool = false,
        isShowingPythonPicker: Bool = false,
        installProgressLog: String = "",
        pipIndexUrl: String = "https://pypi.tuna.tsinghua.edu.cn/simple",
        isShowingPipMirrorEditor: Bool = false
    ) {
        self.activeTab = activeTab
        self.memoryEntries = memoryEntries
        self.userProfileEntries = userProfileEntries
        self.isLoadingMemories = isLoadingMemories
        self.isLoadingUserProfile = isLoadingUserProfile
        self.errorMessage = errorMessage
        self.activeProvider = activeProvider
        self.providerStatus = providerStatus
        self.providerStatusMessage = providerStatusMessage
        self.providerEndpoint = providerEndpoint
        self.pythonPath = pythonPath
        self.pythonCandidates = pythonCandidates
        self.isScanningPython = isScanningPython
        self.isShowingPythonPicker = isShowingPythonPicker
        self.installProgressLog = installProgressLog
        self.pipIndexUrl = pipIndexUrl
        self.isShowingPipMirrorEditor = isShowingPipMirrorEditor
    }

    // MARK: Computed

    /// 当前 Tab 下可见的条目数。
    var totalEntries: Int {
        switch activeTab {
        case .memory:      return memoryEntries.count
        case .userProfile: return userProfileEntries.count
        case .providers:   return 0
        }
    }

    /// 当前 Tab 下已使用字符数。
    var usedCapacity: Int {
        switch activeTab {
        case .memory:
            return memoryEntries.reduce(0) { $0 + $1.content.count }
        case .userProfile:
            return userProfileEntries.reduce(0) { $0 + $1.content.count }
        case .providers:
            return 0
        }
    }

    /// 容量上限 50K 字符 — 对齐 Flutter `maxCapacity`。
    let maxCapacity: Int = 50_000

    /// 当前激活 Provider 是否正在运行。
    var isProviderActive: Bool {
        activeProvider != nil && providerStatus == .running
    }
}
