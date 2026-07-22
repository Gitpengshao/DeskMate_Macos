import Foundation

// MARK: - Skill Category Group

/// Hermes 技能分类分组。
struct SkillCategoryGroup: Equatable, Identifiable {
    let name: String
    let skills: [SkillItem]

    /// 唯一 id，用作 SwiftUI `ForEach` 的 id。
    var id: String { name }
}

// MARK: - Skill Item

/// 技能条目 — 与 Dashboard `GET /api/skills` 返回字段对齐。
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
    /// 是否已启用。
    let isEnabled: Bool
    /// 是否正在提交状态变更（用于按钮/开关 loading）。
    let isToggling: Bool

    init(
        id: String,
        name: String,
        description: String,
        category: String,
        path: String,
        docUrl: String? = nil,
        isEnabled: Bool = false,
        isToggling: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.path = path
        self.docUrl = docUrl
        self.isEnabled = isEnabled
        self.isToggling = isToggling
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
            isEnabled: newEnabled,
            isToggling: isToggling
        )
    }

    /// 仅更新 isToggling 字段。
    func updatingToggling(_ newToggling: Bool) -> SkillItem {
        SkillItem(
            id: id,
            name: name,
            description: description,
            category: category,
            path: path,
            docUrl: docUrl,
            isEnabled: isEnabled,
            isToggling: newToggling
        )
    }
}

// MARK: - Page State Model

/// 技能管理页的单一状态源。
struct SkillManagementModel: Equatable {
    var skills: [SkillCategoryGroup]
    var isLoading: Bool
    var isRefreshing: Bool
    var errorMessage: String?
    /// 当前选中的分类标题（`nil` 表示显示全部）。
    var selectedCategory: String?

    init(
        skills: [SkillCategoryGroup] = [],
        isLoading: Bool = true,
        isRefreshing: Bool = false,
        errorMessage: String? = nil,
        selectedCategory: String? = nil
    ) {
        self.skills = skills
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.errorMessage = errorMessage
        self.selectedCategory = selectedCategory
    }

    // MARK: Computed

    /// 扁平化的所有技能。
    var allSkills: [SkillItem] {
        skills.flatMap { $0.skills }
    }

    /// 已启用技能数。
    var enabledCount: Int {
        allSkills.filter { $0.isEnabled }.count
    }

    /// 根据 `selectedCategory` 过滤后的分类列表。
    var filteredSkills: [SkillCategoryGroup] {
        guard let selectedCategory else { return skills }
        return skills.filter { $0.name == selectedCategory }
    }

    /// 所有分类名称与对应技能数量（用于顶部 Tag 筛选）。
    var allCategories: [(name: String, count: Int)] {
        skills.map { (name: $0.name, count: $0.skills.count) }
    }
}
