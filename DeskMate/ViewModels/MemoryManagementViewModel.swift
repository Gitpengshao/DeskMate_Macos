import Foundation
import Combine

/// 记忆管理页 ViewModel — MVVM 单一状态源。
///
/// 所有状态通过 `model: MemoryManagementModel` 发布；
/// View 通过 `@Published` 订阅更新。所有文件 I/O 均为异步。
@MainActor
final class MemoryManagementViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var model: MemoryManagementModel = MemoryManagementModel()

    // MARK: - Dependencies

    private let store: MemoryFileStore
    private let configWriter: HermesConfigWriter

    // MARK: - Init

    init(
        store: MemoryFileStore = MemoryFileStore(),
        configWriter: HermesConfigWriter = HermesConfigWriter.shared
    ) {
        self.store = store
        self.configWriter = configWriter

        // 启动时异步加载。
        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    /// 主动销毁时的清理入口。
    func dispose() {
        // 当前无外部资源需要释放。
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        await loadMemoryConfig()
        await loadMemories()
        await loadUserProfile()
        await loadSoulProfile()
    }

    // MARK: - Memory config toggles

    /// 从 `config.yaml` 读取 `memory.memory_enabled` 与 `memory.user_profile_enabled`。
    func loadMemoryConfig() async {
        DMLogger.log("loadMemoryConfig: reading memory block ...", name: "MemoryManagementVM")
        let memoryEnabled = configWriter.readMemoryEnabled()
        let userProfileEnabled = configWriter.readUserProfileEnabled()
        model.memoryEnabled = memoryEnabled
        model.userProfileEnabled = userProfileEnabled
        DMLogger.log(
            "loadMemoryConfig: memoryEnabled=\(memoryEnabled) userProfileEnabled=\(userProfileEnabled)",
            name: "MemoryManagementVM"
        )
    }

    /// 切换 `memory.memory_enabled` 并持久化到 `config.yaml`。
    func setMemoryEnabled(_ enabled: Bool) {
        DMLogger.log("setMemoryEnabled: \(model.memoryEnabled) -> \(enabled)", name: "MemoryManagementVM")
        model.memoryEnabled = enabled
        configWriter.writeMemoryEnabled(enabled)
    }

    /// 切换 `memory.user_profile_enabled` 并持久化到 `config.yaml`。
    func setUserProfileEnabled(_ enabled: Bool) {
        DMLogger.log("setUserProfileEnabled: \(model.userProfileEnabled) -> \(enabled)", name: "MemoryManagementVM")
        model.userProfileEnabled = enabled
        configWriter.writeUserProfileEnabled(enabled)
    }

    // MARK: - Tab switching

    /// 切换 Tab。
    func switchTab(_ tab: MemoryTab) {
        DMLogger.log("MemoryMgmt: switchTab -> \(tab.rawValue)", name: "MemoryManagementVM")
        model.activeTab = tab
        model.errorMessage = nil
    }

    /// 清除错误消息。
    func clearError() {
        model.errorMessage = nil
    }

    // MARK: - Memory entries (MEMORY.md)

    /// 读取 MEMORY.md 条目。
    func loadMemories() async {
        DMLogger.log("_loadMemories: reading MEMORY.md ...", name: "MemoryManagementVM")
        model.isLoadingMemories = true
        model.errorMessage = nil
        defer { model.isLoadingMemories = false }
        do {
            let entries = try store.readEntries(.memory)
            DMLogger.log(
                "_loadMemories: got \(entries.count) entries",
                name: "MemoryManagementVM"
            )
            model.memoryEntries = entries
        } catch {
            DMLogger.error(
                "_loadMemories: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 新增一条记忆。
    func addMemoryEntry(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        DMLogger.log("addMemoryEntry: appending to MEMORY.md ...", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.memory)
            let nextIndex = entries.isEmpty ? 0 : (entries.last?.index ?? 0) + 1
            entries.append(MemoryEntry(target: .memory, index: nextIndex, content: trimmed))
            try store.writeEntries(.memory, entries: entries)
            DMLogger.log("addMemoryEntry: saved OK", name: "MemoryManagementVM")
            await loadMemories()
        } catch {
            DMLogger.error(
                "addMemoryEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 编辑一条记忆。
    func editMemoryEntry(_ entryId: String, newContent: String) async {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        DMLogger.log("editMemoryEntry: updating \(entryId)", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.memory)
            guard let index = indexFromId(entryId), index >= 0, index < entries.count else {
                return
            }
            entries[index] = entries[index].updatingContent(trimmed)
            try store.writeEntries(.memory, entries: entries)
            DMLogger.log("editMemoryEntry: updated OK", name: "MemoryManagementVM")
            await loadMemories()
        } catch {
            DMLogger.error(
                "editMemoryEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 删除一条记忆。
    func deleteMemoryEntry(_ entryId: String) async {
        DMLogger.log("deleteMemoryEntry: deleting \(entryId)", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.memory)
            guard let index = indexFromId(entryId), index >= 0, index < entries.count else {
                return
            }
            entries.remove(at: index)
            try store.writeEntries(.memory, entries: entries)
            DMLogger.log("deleteMemoryEntry: deleted OK", name: "MemoryManagementVM")
            await loadMemories()
        } catch {
            DMLogger.error(
                "deleteMemoryEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    // MARK: - User Profile entries (USER.md)

    /// 读取 USER.md 条目。
    func loadUserProfile() async {
        DMLogger.log("_loadUserProfile: reading USER.md ...", name: "MemoryManagementVM")
        model.isLoadingUserProfile = true
        model.errorMessage = nil
        defer { model.isLoadingUserProfile = false }
        do {
            let entries = try store.readEntries(.user)
            DMLogger.log(
                "_loadUserProfile: got \(entries.count) entries",
                name: "MemoryManagementVM"
            )
            model.userProfileEntries = entries
        } catch {
            DMLogger.error(
                "_loadUserProfile: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 新增一条用户画像。
    func addUserProfileEntry(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        DMLogger.log("addUserProfileEntry: appending to USER.md ...", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.user)
            let nextIndex = entries.isEmpty ? 0 : (entries.last?.index ?? 0) + 1
            entries.append(MemoryEntry(target: .user, index: nextIndex, content: trimmed))
            try store.writeEntries(.user, entries: entries)
            DMLogger.log("addUserProfileEntry: saved OK", name: "MemoryManagementVM")
            await loadUserProfile()
        } catch {
            DMLogger.error(
                "addUserProfileEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 编辑一条用户画像。
    func editUserProfileEntry(_ entryId: String, newContent: String) async {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        DMLogger.log("editUserProfileEntry: updating \(entryId)", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.user)
            guard let index = indexFromId(entryId), index >= 0, index < entries.count else {
                return
            }
            entries[index] = entries[index].updatingContent(trimmed)
            try store.writeEntries(.user, entries: entries)
            DMLogger.log("editUserProfileEntry: updated OK", name: "MemoryManagementVM")
            await loadUserProfile()
        } catch {
            DMLogger.error(
                "editUserProfileEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 删除一条用户画像。
    func deleteUserProfileEntry(_ entryId: String) async {
        DMLogger.log("deleteUserProfileEntry: deleting \(entryId)", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.user)
            guard let index = indexFromId(entryId), index >= 0, index < entries.count else {
                return
            }
            entries.remove(at: index)
            try store.writeEntries(.user, entries: entries)
            DMLogger.log("deleteUserProfileEntry: deleted OK", name: "MemoryManagementVM")
            await loadUserProfile()
        } catch {
            DMLogger.error(
                "deleteUserProfileEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Soul Profile (SOUL.md)

    /// 读取 SOUL.md。
    func loadSoulProfile() async {
        DMLogger.log("_loadSoulProfile: reading SOUL.md ...", name: "MemoryManagementVM")
        model.isLoadingSoulProfile = true
        model.errorMessage = nil
        defer { model.isLoadingSoulProfile = false }
        do {
            let content = try store.readSoulFile()
            let entries = content.isEmpty
                ? []
                : [MemoryEntry(target: .soul, index: 0, content: content)]
            DMLogger.log(
                "_loadSoulProfile: got \(content.isEmpty ? "empty" : "content")",
                name: "MemoryManagementVM"
            )
            model.soulProfileEntries = entries
        } catch {
            DMLogger.error(
                "_loadSoulProfile: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 编辑 SOUL.md 完整内容（仅修改，不可新增/删除）。
    func editSoulProfileEntry(_ entryId: String, newContent: String) async {
        guard entryId.hasPrefix("soul_") else { return }
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        DMLogger.log("editSoulProfileEntry: updating SOUL.md", name: "MemoryManagementVM")
        do {
            try store.writeSoulFile(trimmed)
            DMLogger.log("editSoulProfileEntry: updated OK", name: "MemoryManagementVM")
            await loadSoulProfile()
        } catch {
            DMLogger.error(
                "editSoulProfileEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// 从形如 `memory_3` / `user_0` / `soul_0` 的 id 中提取 index。
    private func indexFromId(_ id: String) -> Int? {
        let parts = id.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return Int(parts[1])
    }
}
