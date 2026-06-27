import Foundation

// MARK: - Skill Filter Tab

/// 技能管理页的 Tab 类型 — 对齐 Flutter `SkillFilterTab`。
enum SkillFilterTab: String, Equatable, CaseIterable, Identifiable {
    case builtIn    // 内置技能
    case available  // 可用技能

    var id: String { rawValue }
}

// MARK: - Skill Category Group

/// Hermes 技能分类分组 — 对齐 Flutter `SkillCategoryGroup`。
struct SkillCategoryGroup: Equatable, Identifiable {
    let name: String
    let skills: [SkillItem]

    /// 唯一 id，用作 SwiftUI `ForEach` 的 id。
    var id: String { name }
}

// MARK: - Skill Item

/// 技能条目 — 对齐 Flutter `SkillItem`。
struct SkillItem: Equatable, Identifiable {
    let id: String
    let name: String
    let description: String
    /// 目录名，例如 "creative" / "apple"。
    let category: String
    /// 相对路径，例如 "apple/apple-notes"。
    let path: String
    /// 文档 URL（可为空）。
    let docUrl: String?
    /// 是否已启用/安装。
    let isEnabled: Bool

    init(
        id: String,
        name: String,
        description: String,
        category: String,
        path: String,
        docUrl: String? = nil,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.path = path
        self.docUrl = docUrl
        self.isEnabled = isEnabled
    }

    /// 仅更新 isEnabled 字段，保留其它字段不变。
    func updatingEnabled(_ newEnabled: Bool) -> SkillItem {
        SkillItem(
            id: id,
            name: name,
            description: description,
            category: category,
            path: path,
            docUrl: docUrl,
            isEnabled: newEnabled
        )
    }
}

// MARK: - Page State Model

/// 技能管理页的单一状态源 — 对齐 Flutter `SkillManagementModel`。
struct SkillManagementModel: Equatable {
    var activeTab: SkillFilterTab
    var builtInSkills: [SkillCategoryGroup]
    var availableSkills: [SkillCategoryGroup]
    var isLoading: Bool

    init(
        activeTab: SkillFilterTab = .builtIn,
        builtInSkills: [SkillCategoryGroup] = [],
        availableSkills: [SkillCategoryGroup] = [],
        isLoading: Bool = true
    ) {
        self.activeTab = activeTab
        self.builtInSkills = builtInSkills
        self.availableSkills = availableSkills
        self.isLoading = isLoading
    }

    // MARK: Computed

    /// 当前激活 Tab 下的所有技能（扁平）。
    var activeSkills: [SkillItem] {
        let groups = (activeTab == .builtIn) ? builtInSkills : availableSkills
        return groups.flatMap { $0.skills }
    }

    /// 当前激活 Tab 下的分类分组。
    var activeGroups: [SkillCategoryGroup] {
        (activeTab == .builtIn) ? builtInSkills : availableSkills
    }

    /// 两个 Tab 加起来已安装（isEnabled）的技能数。
    var installedCount: Int {
        let allBuiltIn = builtInSkills.flatMap { $0.skills }
        let allAvailable = availableSkills.flatMap { $0.skills }
        return (allBuiltIn + allAvailable).filter { $0.isEnabled }.count
    }
}
