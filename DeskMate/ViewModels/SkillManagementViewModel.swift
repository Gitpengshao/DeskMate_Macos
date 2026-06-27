import Foundation
import AppKit
import Combine

/// 技能管理页 ViewModel — 一比一还原 Flutter `SkillManagementViewModel`。
///
/// MVVM 单一状态源：所有状态通过 `model: SkillManagementModel` 发布；
/// View 通过 `@Published` 订阅更新。所有文件系统 I/O 均为异步。
@MainActor
final class SkillManagementViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var model: SkillManagementModel = SkillManagementModel()

    // MARK: - Dependencies

    private let scanner: SkillScannerService
    private let installer: SkillInstallService

    // MARK: - Init

    init(scanner: SkillScannerService = SkillScannerService(),
         installer: SkillInstallService = .shared) {
        self.scanner = scanner
        self.installer = installer
        // 启动时异步加载 — 对齐 Flutter `build()` 内的 `_loadSkills()` 行为
        Task { [weak self] in
            await self?.loadSkills()
        }
    }

    // MARK: - Loading

    /// 扫描两个数据源并将结果归类:
    /// - `~/.hermes/skills/` — 已安装技能,按 `.bundled_manifest` 区分内置/用户安装
    /// - `~/.hermes/hermes-agent/optional-skills/` — 官方随包发布的可选技能目录
    ///
    /// 对齐 Flutter `_loadSkills`,并扩展以支持官方可选技能。
    func loadSkills() async {
        DMLogger.log("SkillMgmt: scanning skills ...", name: "SkillManagementVM")
        model.isLoading = true
        defer { model.isLoading = false }

        // 1. 扫描已安装技能
        let installed: [String: [RawSkillInfo]]
        do {
            installed = try scanner.scanSkills()
        } catch {
            DMLogger.error(
                "SkillMgmt: scan installed failed \(error.localizedDescription)",
                name: "SkillManagementVM"
            )
            installed = [:]
        }

        // 2. 扫描官方可选技能
        let optional: [String: [OptionalSkillInfo]]
        do {
            optional = try scanner.scanOptionalSkills()
        } catch {
            DMLogger.error(
                "SkillMgmt: scan optional failed \(error.localizedDescription)",
                name: "SkillManagementVM"
            )
            optional = [:]
        }

        var builtIn: [SkillCategoryGroup] = []
        var available: [SkillCategoryGroup] = []

        // 3. 合并所有分类名(已安装 + 可选),保证分类显示稳定
        let allCategories = Set(installed.keys).union(optional.keys)
        let sortedCategories = allCategories.sorted()

        for category in sortedCategories {
            // 3.1 内置技能 = 该分类下 isBuiltIn=true 的已安装技能
            let builtInSkills: [SkillItem] = (installed[category] ?? [])
                .filter { $0.isBuiltIn }
                .map { raw in
                    let display = SkillCatalog.displayInfo(for: raw.id)
                    return SkillItem(
                        id: raw.id,
                        name: display?.name ?? raw.id,
                        description: display?.description ?? "",
                        category: raw.category,
                        path: raw.path,
                        isEnabled: raw.isEnabled
                    )
                }
                .sorted { $0.id < $1.id }

            // 3.2 可用技能 = 官方 optional-skills 目录下的技能(已安装/未安装都算)
            //     + 已安装但非内置的用户自定义技能
            let optSkills: [SkillItem] = (optional[category] ?? [])
                .map { raw in
                    let display = SkillCatalog.displayInfo(for: raw.id)
                    return SkillItem(
                        id: raw.id,
                        name: display?.name ?? raw.id,
                        description: display?.description ?? "",
                        category: raw.category,
                        path: raw.path,
                        isEnabled: raw.isInstalled
                    )
                }
                .sorted { $0.id < $1.id }

            let userSkills: [SkillItem] = (installed[category] ?? [])
                .filter { !$0.isBuiltIn }
                .map { raw in
                    let display = SkillCatalog.displayInfo(for: raw.id)
                    return SkillItem(
                        id: raw.id,
                        name: display?.name ?? raw.id,
                        description: display?.description ?? "",
                        category: raw.category,
                        path: raw.path,
                        isEnabled: raw.isEnabled
                    )
                }
                .sorted { $0.id < $1.id }

            // 合并时按 id 去重(用户已安装的官方技能只保留一次,优先用 installed 的显示信息)
            var seenIds: Set<String> = []
            var availableSkills: [SkillItem] = []
            for skill in (optSkills + userSkills) {
                if seenIds.insert(skill.id).inserted {
                    availableSkills.append(skill)
                }
            }

            let categoryTitle = Self.formatCategoryName(category)

            if !builtInSkills.isEmpty {
                builtIn.append(SkillCategoryGroup(name: categoryTitle, skills: builtInSkills))
            }
            if !availableSkills.isEmpty {
                available.append(SkillCategoryGroup(name: categoryTitle, skills: availableSkills))
            }
        }

        DMLogger.log(
            "SkillMgmt: builtIn=\(builtIn.count) cats, available=\(available.count) cats",
            name: "SkillManagementVM"
        )
        model.builtInSkills = builtIn
        model.availableSkills = available
    }

    /// 重新从磁盘加载 — 对齐 Flutter `refreshSkills()`。
    func refreshSkills() async {
        model.isLoading = true
        await loadSkills()
    }

    // MARK: - Tab switching

    /// 切换 Tab — 对齐 Flutter `switchTab`。
    func switchTab(_ tab: SkillFilterTab) {
        DMLogger.log("SkillMgmt: switchTab -> \(tab.rawValue)", name: "SkillManagementVM")
        model.activeTab = tab
    }

    // MARK: - Skill state mutations

    /// 切换技能启用状态 — 对齐 Flutter `toggleSkill`。
    func toggleSkill(_ skillId: String) {
        model = updateSkill(in: model, skillId: skillId) { $0.updatingEnabled(!$0.isEnabled) }
    }

    /// 安装（启用）一个可选技能 — 实际执行 `hermes skills install official/<cat>/<id>`，
    /// 安装完成后重新扫描磁盘以同步状态。
    func installSkill(_ skillId: String) {
        DMLogger.log("SkillMgmt: install \(skillId)", name: "SkillManagementVM")
        guard let category = findCategory(forSkill: skillId) else {
            DMLogger.error(
                "SkillMgmt: install failed, category not found for \(skillId)",
                name: "SkillManagementVM"
            )
            return
        }
        // 立即在 UI 上反映"安装中"状态
        model = updateSkill(in: model, skillId: skillId) { $0.updatingEnabled(true) }
        Task { [weak self] in
            guard let self else { return }
            let ok = await self.installer.install(category: category, skillId: skillId)
            if !ok {
                DMLogger.error(
                    "SkillMgmt: install failed for \(skillId), reverting UI",
                    name: "SkillManagementVM"
                )
                await MainActor.run {
                    self.model = self.updateSkill(in: self.model, skillId: skillId) {
                        $0.updatingEnabled(false)
                    }
                }
            }
            // 重新从磁盘扫描,确保 isEnabled / isInstalled 与 CLI 真实状态一致
            await self.refreshSkills()
        }
    }

    /// 卸载一个已安装的可选技能 — 实际执行 `hermes skills uninstall <id>`。
    func uninstallSkill(_ skillId: String) {
        DMLogger.log("SkillMgmt: uninstall \(skillId)", name: "SkillManagementVM")
        // 立即在 UI 上反映"卸载中"状态
        model = updateSkill(in: model, skillId: skillId) { $0.updatingEnabled(false) }
        Task { [weak self] in
            guard let self else { return }
            let ok = await self.installer.uninstall(skillId: skillId)
            if !ok {
                DMLogger.error(
                    "SkillMgmt: uninstall failed for \(skillId), reverting UI",
                    name: "SkillManagementVM"
                )
                await MainActor.run {
                    self.model = self.updateSkill(in: self.model, skillId: skillId) {
                        $0.updatingEnabled(true)
                    }
                }
            }
            await self.refreshSkills()
        }
    }

    /// 还原一个内置技能（重新启用）— 对齐 Flutter `restoreSkill`。
    func restoreSkill(_ skillId: String) {
        DMLogger.log("SkillMgmt: restore \(skillId)", name: "SkillManagementVM")
        model = updateSkill(in: model, skillId: skillId) { $0.updatingEnabled(true) }
    }

    // MARK: - Registry

    /// 打开官方可选技能市场文档 — 对齐 Flutter `_HeaderBar` 的「浏览技能市场」按钮。
    ///
    /// 当前阶段没有真正的内建市场，因此用 NSWorkspace 跳到官方文档，
    /// 让用户可以浏览完整可选技能清单与每项详情。
    func browseRegistry() {
        let urlString = "https://hermes-agent.nousresearch.com/docs/zh-Hans/reference/optional-skills-catalog"
        DMLogger.log("SkillMgmt: browseRegistry -> \(urlString)", name: "SkillManagementVM")
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    /// 在两个 Tab 的所有分类中查找并更新指定 skill。
    private func updateSkill(
        in model: SkillManagementModel,
        skillId: String,
        updater: (SkillItem) -> SkillItem
    ) -> SkillManagementModel {
        var newModel = model
        newModel.builtInSkills = model.builtInSkills.map { updateGroup($0, skillId: skillId, updater: updater) }
        newModel.availableSkills = model.availableSkills.map { updateGroup($0, skillId: skillId, updater: updater) }
        return newModel
    }

    private func updateGroup(
        _ group: SkillCategoryGroup,
        skillId: String,
        updater: (SkillItem) -> SkillItem
    ) -> SkillCategoryGroup {
        SkillCategoryGroup(
            name: group.name,
            skills: group.skills.map { $0.id == skillId ? updater($0) : $0 }
        )
    }

    /// 在当前 model 中查找指定 skillId 的 category 目录名。
    /// 优先在 available 列表中查找(可选技能从这里安装),其次 builtIn。
    private func findCategory(forSkill skillId: String) -> String? {
        for group in model.availableSkills {
            if let s = group.skills.first(where: { $0.id == skillId }) {
                return s.category
            }
        }
        for group in model.builtInSkills {
            if let s = group.skills.first(where: { $0.id == skillId }) {
                return s.category
            }
        }
        return nil
    }

    /// 分类目录名 → 人类可读 Title（"claude-code" → "Claude Code"）— 对齐 Flutter `_formatCategoryName`。
    static func formatCategoryName(_ dirName: String) -> String {
        return dirName
            .split(separator: "-")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}
