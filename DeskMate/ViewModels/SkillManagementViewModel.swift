import Foundation
import AppKit
import Combine

/// 技能管理页 ViewModel — 从 Dashboard API 获取技能并管理启用状态。
///
/// 数据来源：`GET /api/skills` / `PUT /api/skills/toggle`。
/// 创建技能：按官方 `creating-skills` 指南在 `~/.hermes/skills/` 下写入 SKILL.md。
@MainActor
final class SkillManagementViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var model: SkillManagementModel = SkillManagementModel()

    // MARK: - Dependencies

    private let client: DashboardClient

    // MARK: - Cache

    /// 内存缓存，避免每次进入页面都重新拉取，提升 reopen/toggle 体验。
    private static var cachedSkills: [SkillCategoryGroup]?

    // MARK: - Init

    init(client: DashboardClient = .shared) {
        self.client = client
        Task { [weak self] in
            await self?.setupInitialLoad()
        }
    }

    private func setupInitialLoad() async {
        if let cached = Self.cachedSkills, !cached.isEmpty {
            model.skills = cached
            model.isLoading = false
            await refreshSkills()
        } else {
            await loadSkills()
        }
    }

    // MARK: - Loading

    /// 从 Dashboard API 加载技能列表。
    func loadSkills() async {
        DMLogger.log("SkillMgmt: loading skills from API ...", name: "SkillManagementVM")
        if model.skills.isEmpty {
            model.isLoading = true
        } else {
            model.isRefreshing = true
        }
        model.errorMessage = nil
        defer {
            model.isLoading = false
            model.isRefreshing = false
        }

        guard let rawSkills = await client.getSkills() else {
            model.errorMessage = "无法从 Dashboard 获取技能列表，请确认 `hermes dashboard` 已启动。"
            DMLogger.error("SkillMgmt: failed to fetch skills from API", name: "SkillManagementVM")
            return
        }

        var groups: [String: [SkillItem]] = [:]
        for raw in rawSkills {
            guard let name = raw["name"] as? String, !name.isEmpty else { continue }
            let description = raw["description"] as? String ?? ""
            let category = raw["category"] as? String ?? "Uncategorized"
            let enabled = raw["enabled"] as? Bool ?? false

            let item = SkillItem(
                id: name,
                name: name,
                description: description,
                category: category,
                path: "\(category)/\(name)",
                isEnabled: enabled
            )
            groups[category, default: []].append(item)
        }

        let sortedCategories = groups.keys.sorted()
        model.skills = sortedCategories.map { category in
            let skills = (groups[category] ?? [])
                .sorted { $0.name < $1.name }
            return SkillCategoryGroup(
                name: Self.formatCategoryName(category),
                skills: skills
            )
        }
        Self.cachedSkills = model.skills
        model.errorMessage = nil

        DMLogger.log(
            "SkillMgmt: loaded \(model.skills.count) categories, \(model.allSkills.count) skills",
            name: "SkillManagementVM"
        )
    }

    /// 重新加载技能列表（有缓存时后台刷新，避免页面滚动位置重置）。
    func refreshSkills() async {
        await loadSkills()
    }

    // MARK: - Skill state mutations

    /// 切换技能启用状态 — 调用 `PUT /api/skills/toggle`。
    ///
    /// 成功/失败均只修改本地对应条目，不重新拉取全量列表，从而保留滚动位置与缓存。
    func toggleSkill(_ skillId: String) {
        guard let skill = findSkill(by: skillId) else { return }
        let newEnabled = !skill.isEnabled

        DMLogger.log(
            "SkillMgmt: toggle \(skillId) -> \(newEnabled)",
            name: "SkillManagementVM"
        )

        // 立即在 UI 上反映变更并进入 loading。
        model = updateSkill(skillId: skillId) { $0.updatingEnabled(newEnabled).updatingToggling(true) }

        Task { [weak self] in
            guard let self else { return }
            let ok = await self.client.toggleSkill(name: skillId, enabled: newEnabled)
            if !ok {
                DMLogger.error(
                    "SkillMgmt: toggle failed for \(skillId), reverting UI",
                    name: "SkillManagementVM"
                )
                self.model = self.updateSkill(skillId: skillId) {
                    $0.updatingEnabled(!newEnabled).updatingToggling(false)
                }
                self.model.errorMessage = "切换技能状态失败：\(skillId)"
                return
            }
            // 仅更新本地状态，不刷新全量列表，避免滚动回顶。
            self.model = self.updateSkill(skillId: skillId) { $0.updatingToggling(false) }
            self.syncCache()
        }
    }

    /// 选择/取消选择分类筛选。
    func selectCategory(_ name: String?) {
        model.selectedCategory = name
    }

    /// 将当前 skills 同步到内存缓存。
    private func syncCache() {
        Self.cachedSkills = model.skills
    }

    // MARK: - Create skill

    /// 创建本地自定义技能。
    ///
    /// 按官方 `creating-skills` 指南，在 `~/.hermes/skills/<category>/<name>/SKILL.md`
    /// 写入 YAML frontmatter + 用户提供的正文。
    /// - Returns: 是否成功。
    func createSkill(name: String, description: String, category: String, content: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedCategory.isEmpty else { return false }

        let slug = Self.slugify(trimmedName)
        let categorySlug = Self.slugify(trimmedCategory)
        let skillsDir = SkillScannerService.installedSkillsDir()
        let skillDir = skillsDir.appendingPathComponent(categorySlug, isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
        let skillMd = skillDir.appendingPathComponent("SKILL.md")

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
            let body = """
            ---
            name: \(slug)
            description: \(trimmedDesc)
            version: 1.0.0
            metadata:
              hermes:
                tags: [\(categorySlug)]
            ---

            \(trimmedContent.isEmpty ? "# \(trimmedName)\n\n\(trimmedDesc)" : trimmedContent)
            """
            try body.write(to: skillMd, atomically: true, encoding: .utf8)
            DMLogger.log(
                "SkillMgmt: created skill at \(skillMd.path)",
                name: "SkillManagementVM"
            )
            await refreshSkills()
            return true
        } catch {
            DMLogger.error(
                "SkillMgmt: failed to create skill \(error.localizedDescription)",
                name: "SkillManagementVM"
            )
            model.errorMessage = "创建技能失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Registry

    /// 打开官方可选技能市场文档。
    func browseRegistry() {
        let urlString = "https://hermes-agent.nousresearch.com/docs/zh-Hans/reference/optional-skills-catalog"
        DMLogger.log("SkillMgmt: browseRegistry -> \(urlString)", name: "SkillManagementVM")
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func findSkill(by skillId: String) -> SkillItem? {
        model.allSkills.first { $0.id == skillId }
    }

    private func updateSkill(
        skillId: String,
        updater: (SkillItem) -> SkillItem
    ) -> SkillManagementModel {
        var newModel = model
        newModel.skills = model.skills.map { group in
            SkillCategoryGroup(
                name: group.name,
                skills: group.skills.map { $0.id == skillId ? updater($0) : $0 }
            )
        }
        return newModel
    }

    /// 分类目录名 → 人类可读 Title（"claude-code" → "Claude Code"）。
    static func formatCategoryName(_ dirName: String) -> String {
        return dirName
            .split(separator: "-")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    /// 将技能名/分类转换为目录安全的小写连字符形式。
    static func slugify(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return input
            .lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
