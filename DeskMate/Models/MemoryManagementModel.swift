import Foundation

// MARK: - Memory Tab

/// 记忆管理页的三个 Tab 类型。
///
/// - **记忆**     — `~/.hermes/memories/MEMORY.md` 条目（agent permanent memory / notes）
/// - **用户画像** — `~/.hermes/memories/USER.md` 条目（user preferences）
/// - **灵魂画像** — `~/.hermes/SOUL.md` 文件（agent soul / personality）
enum MemoryTab: String, Equatable, CaseIterable, Identifiable {
    case memory       // MEMORY.md
    case userProfile  // USER.md
    case soulProfile  // SOUL.md

    var id: String { rawValue }
}

// MARK: - Memory Target

/// 记忆条目所属文件。
///
/// `memory` / `user` 使用 `§` 段分隔符存储为多条；`soul` 为单文件整体编辑。
enum MemoryTarget: String, Equatable, Codable {
    case memory
    case user
    case soul
}

// MARK: - Memory Entry

/// 一条记忆条目，存放在 `~/.hermes/memories/MEMORY.md`、`USER.md`，
/// 或 `~/.hermes/SOUL.md` 的完整内容。
///
/// Hermes 使用 `§` 作为 MEMORY.md / USER.md 的段分隔符；SOUL.md 视为单一条目。
struct MemoryEntry: Identifiable, Equatable, Codable {
    /// MEMORY.md / USER.md / SOUL.md。
    let target: MemoryTarget
    /// 在文件中的索引，用于定位编辑。
    let index: Int
    /// 条目内容。
    let content: String

    /// 唯一 id，组合 target 与 index。
    var id: String { "\(target.rawValue)_\(index)" }

    nonisolated init(target: MemoryTarget, index: Int, content: String) {
        self.target = target
        self.index = index
        self.content = content
    }

    /// 仅更新内容（保持 target/index 不变），用于编辑。
    func updatingContent(_ newContent: String) -> MemoryEntry {
        MemoryEntry(target: target, index: index, content: newContent)
    }
}

// MARK: - Page State Model

/// 记忆管理页的单一状态源。
struct MemoryManagementModel: Equatable {
    var activeTab: MemoryTab

    /// MEMORY.md 条目（agent permanent memory / notes）。
    var memoryEntries: [MemoryEntry]
    /// USER.md 条目（user profile / preferences）。
    var userProfileEntries: [MemoryEntry]
    /// SOUL.md 单一条目（agent soul / personality）。
    var soulProfileEntries: [MemoryEntry]

    var isLoadingMemories: Bool
    var isLoadingUserProfile: Bool
    var isLoadingSoulProfile: Bool
    var errorMessage: String?

    init(
        activeTab: MemoryTab = .memory,
        memoryEntries: [MemoryEntry] = [],
        userProfileEntries: [MemoryEntry] = [],
        soulProfileEntries: [MemoryEntry] = [],
        isLoadingMemories: Bool = false,
        isLoadingUserProfile: Bool = false,
        isLoadingSoulProfile: Bool = false,
        errorMessage: String? = nil
    ) {
        self.activeTab = activeTab
        self.memoryEntries = memoryEntries
        self.userProfileEntries = userProfileEntries
        self.soulProfileEntries = soulProfileEntries
        self.isLoadingMemories = isLoadingMemories
        self.isLoadingUserProfile = isLoadingUserProfile
        self.isLoadingSoulProfile = isLoadingSoulProfile
        self.errorMessage = errorMessage
    }

    // MARK: Computed

    /// 当前 Tab 下可见的条目数。
    var totalEntries: Int {
        switch activeTab {
        case .memory:      return memoryEntries.count
        case .userProfile: return userProfileEntries.count
        case .soulProfile: return soulProfileEntries.count
        }
    }

    /// 当前 Tab 下已使用字符数。
    var usedCapacity: Int {
        switch activeTab {
        case .memory:
            return memoryEntries.reduce(0) { $0 + $1.content.count }
        case .userProfile:
            return userProfileEntries.reduce(0) { $0 + $1.content.count }
        case .soulProfile:
            return soulProfileEntries.reduce(0) { $0 + $1.content.count }
        }
    }

    /// 容量上限 50K 字符。
    let maxCapacity: Int = 50_000
}
