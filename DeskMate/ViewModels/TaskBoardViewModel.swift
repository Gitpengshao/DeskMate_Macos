import Foundation
import Combine

/// 任务看板页 ViewModel。
///
/// MVVM 单一状态源：所有状态通过 `model: TaskBoardPageModel` 发布；
/// View 通过 `@Published` 订阅更新。所有 CLI 写入均为异步，最终结果在
/// `@MainActor` 上 commit 到 `model`。
@MainActor
final class TaskBoardViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var model: TaskBoardPageModel = TaskBoardPageModel(
        isLoading: true
    )

    // MARK: - Dependencies

    private let service: TaskBoardService

    // MARK: - Agent Profiles

    /// 当前可选的 Hermes profile，供新建任务时选择 Agent。
    var agentProfiles: [AgentProfile] {
        AgentViewModel.shared.model.profiles
    }

    /// 为指定 profile 推断默认工作目录。
    func defaultWorkspace(for profile: AgentProfile?) -> String {
        guard let profile else { return NSHomeDirectory() }
        let fm = FileManager.default
        // 优先使用 profile 路径本身作为工作区（若存在）
        if !profile.path.isEmpty, fm.fileExists(atPath: profile.path) {
            return profile.path
        }
        return NSHomeDirectory()
    }

    // MARK: - Init

    init(service: TaskBoardService = .shared) {
        self.service = service
        // 启动时异步加载。
        Task { [weak self] in
            await self?.fetchFromApi()
        }
    }

    // MARK: - API Integration

    /// 拉取所有看板与当前活跃看板的任务列表。
    func fetchFromApi() async {
        DMLogger.log(
            "[TaskBoardVM] _fetchFromApi() 开始请求 Gateway API…",
            name: "TaskBoardVM"
        )
        model = model.updating(isLoading: true, clearError: true)

        do {
            let boardsJson = try await service.getKanbanBoards() ?? []
            DMLogger.log(
                "[TaskBoardVM] getKanbanBoards → \(boardsJson.count) 条",
                name: "TaskBoardVM"
            )
            for (i, b) in boardsJson.enumerated() {
                DMLogger.log(
                    "[TaskBoardVM] board[\(i)] raw: \(b)",
                    name: "TaskBoardVM"
                )
            }

            if !boardsJson.isEmpty {
                let boards = boardsJson.map { TaskBoard.fromJson($0) }
                for (i, b) in boards.enumerated() {
                    DMLogger.log(
                        "[TaskBoardVM] board[\(i)] parsed: id=\(b.id), slug=\(b.slug), name=\(b.name), taskCount=\(b.taskCount)",
                        name: "TaskBoardVM"
                    )
                }

                // 选择 activeSlug
                let currentBoard = boards.first(where: { $0.id == model.activeBoardId })
                let activeSlug: String = {
                    if let cur = currentBoard { return cur.slug }
                    return boards.first?.slug ?? "default"
                }()
                DMLogger.log(
                    "[TaskBoardVM] activeBoardId=\(model.activeBoardId), currentBoard=\(currentBoard?.slug ?? "nil"), selected activeSlug=\"\(activeSlug)\"",
                    name: "TaskBoardVM"
                )

                let tasks = await loadTasksForBoard(slug: activeSlug)
                DMLogger.log(
                    "[TaskBoardVM] API success → boards: \(boards.count), tasks: \(tasks.count), activeSlug: \(activeSlug)",
                    name: "TaskBoardVM"
                )
                model = model.updating(
                    activeBoardId: currentBoard?.id ?? boards.first?.id ?? "",
                    boards: boards,
                    tasks: tasks,
                    isLoading: false,
                    clearError: true
                )
            } else {
                DMLogger.log(
                    "[TaskBoardVM] Gateway 无看板数据，显示空状态",
                    name: "TaskBoardVM"
                )
                model = model.updating(
                    isLoading: false,
                    clearError: true
                )
            }
        } catch {
            DMLogger.error(
                "[TaskBoardVM] _fetchFromApi error: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
            model = model.updating(
                isLoading: false,
                errorMessage: "无法连接到 Hermes Gateway，请确认 Gateway 已启动。"
            )
        }
    }

    /// 刷新数据。
    func refresh() async {
        await fetchFromApi()
    }

    /// 加载某 slug 看板的所有任务。
    private func loadTasksForBoard(slug: String) async -> [TaskItem] {
        DMLogger.log(
            "[TaskBoardVM] _loadTasksForBoard START boardSlug=\"\(slug)\"",
            name: "TaskBoardVM"
        )
        guard let tasksResp = try? await service.getKanbanTasks(boardSlug: slug),
              let dataList = tasksResp["data"] as? [Any]
        else {
            DMLogger.log(
                "[TaskBoardVM] _loadTasksForBoard END → returning [] (no valid data list)",
                name: "TaskBoardVM"
            )
            return []
        }

        DMLogger.log(
            "[TaskBoardVM] getKanbanTasks(\"\(slug)\") data list → \(dataList.count) 条",
            name: "TaskBoardVM"
        )
        for (i, raw) in dataList.enumerated() {
            DMLogger.log(
                "[TaskBoardVM] task[\(i)] raw: \(raw)",
                name: "TaskBoardVM"
            )
        }

        let tasks: [TaskItem] = dataList.enumerated().compactMap { (i, raw) -> TaskItem? in
            guard let dict = raw as? [String: Any] else { return nil }
            let task = TaskItem.fromJson(dict)
            DMLogger.log(
                "[TaskBoardVM] task[\(i)] parsed: id=\(task.id), title=\(task.title), status=\(task.status.rawValue)",
                name: "TaskBoardVM"
            )
            return task
        }
        DMLogger.log(
            "[TaskBoardVM] _loadTasksForBoard END → \(tasks.count) tasks parsed",
            name: "TaskBoardVM"
        )
        return tasks
    }

    // MARK: - Board Operations

    /// 删除（归档）看板。
    func deleteBoard(_ boardId: String) async {
        guard let board = model.boards.first(where: { $0.id == boardId }),
              !board.id.isEmpty
        else { return }

        model = model.updating(isLoading: true)
        defer { model = model.updating(isLoading: false) }

        // 乐观更新本地状态
        let remaining = model.boards.filter { $0.id != boardId }
        let newActiveId: String = {
            if model.activeBoardId == boardId {
                return remaining.first?.id ?? ""
            }
            return model.activeBoardId
        }()
        model = model.updating(
            activeBoardId: newActiveId,
            boards: remaining,
            tasks: (model.activeBoardId == boardId) ? [] : model.tasks
        )

        do {
            let success = try await service.deleteKanbanBoard(slug: board.slug)
            if !success {
                DMLogger.log(
                    "TaskBoardViewModel.deleteBoard API returned false, refreshing",
                    name: "TaskBoardVM"
                )
                await fetchFromApi()
            }
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.deleteBoard API: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
            await fetchFromApi()
        }
    }

    // MARK: - Task Lifecycle (CRUD)

    /// 创建任务。
    func addTask(
        _ title: String,
        status: TaskStatus = .todo,
        priority: String = "P2",
        assignee: String = "",
        body: String = "",
        workspace: String = "",
        tenant: String = "",
        idempotencyKey: String = "",
        branch: String = "",
        skills: [String] = [],
        maxRetries: Int? = nil,
        parentIds: [String] = []
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        model = model.updating(isLoading: true)
        defer { model = model.updating(isLoading: false) }

        do {
            let boardSlug = model.activeBoard?.slug ?? "default"
            let reqBody: [String: Any] = [
                "_board": boardSlug,
                "title": trimmedTitle,
                "status": status.rawValue,
                "priority": priority,
                "assignee": assignee.trimmingCharacters(in: .whitespaces),
                "body": body.trimmingCharacters(in: .whitespaces),
                "workspace": workspace,
                "tenant": tenant,
                "idempotencyKey": idempotencyKey,
                "branch": branch,
                "skills": skills,
                "maxRetries": maxRetries as Any? ?? NSNull(),
                "parentIds": parentIds,
            ]
            DMLogger.log(
                "[TaskBoardVM] addTask request body: \(reqBody)",
                name: "TaskBoardVM"
            )
            if let result = try await service.createKanbanTask(body: reqBody) {
                let task = TaskItem.fromJson(result)
                model = model.updating(tasks: model.tasks + [task])
                DMLogger.log(
                    "[TaskBoardVM] addTask created: \(task.id) \"\(task.title)\"",
                    name: "TaskBoardVM"
                )
            } else {
                DMLogger.log(
                    "[TaskBoardVM] addTask API returned null",
                    name: "TaskBoardVM"
                )
            }
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.addTask API: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    /// 完成任务 — 调用 `hermes kanban complete <id>`。
    func completeTask(_ taskId: String) async {
        let newTasks = model.tasks.map { t -> TaskItem in
            if t.id == taskId {
                return t.updating(status: .done, updatedAt: Date())
            }
            return t
        }
        model = model.updating(tasks: newTasks, isLoading: true)
        defer { model = model.updating(isLoading: false) }
        _ = try? await service.updateKanbanTask(taskId: taskId, body: ["status": "done"])
    }

    /// 阻塞任务 — 调用 `hermes kanban block <id> <reason>`。
    func blockTask(_ taskId: String, reason: String) async {
        let trimmedReason = reason.trimmingCharacters(in: .whitespaces)
        let newTasks = model.tasks.map { t -> TaskItem in
            if t.id == taskId {
                return t.updating(status: .blocked, updatedAt: Date())
            }
            return t
        }
        model = model.updating(tasks: newTasks, isLoading: true)
        defer { model = model.updating(isLoading: false) }
        _ = try? await service.updateKanbanTask(
            taskId: taskId,
            body: ["status": "blocked", "reason": trimmedReason]
        )
    }

    /// 解除阻塞 — 调用 `hermes kanban unblock <id>`。
    func unblockTask(_ taskId: String) async {
        let newTasks = model.tasks.map { t -> TaskItem in
            if t.id == taskId {
                return t.updating(status: .ready, updatedAt: Date())
            }
            return t
        }
        model = model.updating(tasks: newTasks, isLoading: true)
        defer { model = model.updating(isLoading: false) }
        _ = try? await service.updateKanbanTask(taskId: taskId, body: ["status": "ready"])
    }

    /// 归档任务 — 调用 `hermes kanban archive <id>`。
    func archiveTask(_ taskId: String) async {
        let newTasks = model.tasks.map { t -> TaskItem in
            if t.id == taskId {
                return t.updating(status: .archived, updatedAt: Date())
            }
            return t
        }
        model = model.updating(tasks: newTasks, isLoading: true)
        defer { model = model.updating(isLoading: false) }
        _ = try? await service.updateKanbanTask(taskId: taskId, body: ["status": "archived"])
    }

    /// 删除任务（实际走 archive，Hermes Kanban 不支持硬删除）。
    func deleteTask(_ taskId: String) async {
        let previousTasks = model.tasks
        model = model.updating(
            tasks: previousTasks.filter { $0.id != taskId },
            isLoading: true
        )
        defer { model = model.updating(isLoading: false) }
        _ = try? await service.updateKanbanTask(taskId: taskId, body: ["status": "archived"])
    }

    // MARK: - Triage / Display Actions

    /// 切换"Lanes by profile"开关 — Running 列按 profile 分组。
    func setLanesByProfile(_ enabled: Bool) {
        model = model.updating(lanesByProfile: enabled)
    }

    /// 更新顶部筛选条件。
    func setFilter(_ filter: TaskBoardFilter) {
        model = model.updating(filter: filter)
    }

    /// 重置筛选。
    func clearFilter() {
        model = model.updating(filter: TaskBoardFilter())
    }

    /// 手动分解 Triage 任务为子任务 — 对齐官方 `kanban decompose <id>`。
    /// 之后刷新当前看板拉取新生成的子任务。
    func decomposeTask(_ taskId: String) async {
        DMLogger.log(
            "[TaskBoardVM] decomposeTask \(taskId)",
            name: "TaskBoardVM"
        )
        do {
            let success = try await service.decomposeTask(taskId: taskId)
            if success {
                DMLogger.log(
                    "[TaskBoardVM] decomposeTask \(taskId) CLI 成功 → refresh",
                    name: "TaskBoardVM"
                )
                await refresh()
            } else {
                DMLogger.log(
                    "[TaskBoardVM] decomposeTask \(taskId) CLI 失败",
                    name: "TaskBoardVM"
                )
            }
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.decomposeTask: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    /// 把 Triage 任务的粗想法展开为完整 spec(goal / approach / acceptance criteria)
    /// 并提升到 `todo` — 对齐官方 `hermes kanban specify <id>`
    /// (由 `auxiliary.triage_specifier` 模型驱动)。
    ///
    /// 注意:官方语义是 triage → **todo**,**不是** → ready。
    /// 之前的实现错误地调用 moveTask → ready,既走了不存在的 `move` verb,
    /// 又把目标状态搞错。这里直接调用 Service 的 specify verb,然后刷新看板。
    func specifyTask(_ taskId: String) async {
        DMLogger.log(
            "[TaskBoardVM] specifyTask \(taskId) → kanban specify",
            name: "TaskBoardVM"
        )
        do {
            let success = try await service.specifyTask(taskId: taskId)
            if success {
                DMLogger.log(
                    "[TaskBoardVM] specifyTask \(taskId) CLI 成功 → refresh",
                    name: "TaskBoardVM"
                )
                await refresh()
            } else {
                DMLogger.log(
                    "[TaskBoardVM] specifyTask \(taskId) CLI 失败",
                    name: "TaskBoardVM"
                )
            }
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.specifyTask: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    /// 立即触发一次 dispatcher tick — 对齐官方 Nudge 操作。
    /// 调度器会扫描 Ready 任务并把它们分发到 running 状态。
    func nudgeDispatcher() async {
        DMLogger.log("[TaskBoardVM] nudgeDispatcher", name: "TaskBoardVM")
        model = model.updating(isLoading: true)
        defer { model = model.updating(isLoading: false) }
        do {
            let success = try await service.nudgeDispatcher()
            if success {
                DMLogger.log(
                    "[TaskBoardVM] nudgeDispatcher CLI 成功 → refresh",
                    name: "TaskBoardVM"
                )
                await refresh()
            } else {
                DMLogger.log(
                    "[TaskBoardVM] nudgeDispatcher CLI 失败",
                    name: "TaskBoardVM"
                )
            }
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.nudgeDispatcher: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    // MARK: - Run History

    /// 拉取任务运行历史(对齐官方 `kanban runs <id>`)并合并到 task.runHistory。
    func loadTaskRuns(_ taskId: String) async {
        DMLogger.log(
            "[TaskBoardVM] loadTaskRuns \(taskId)",
            name: "TaskBoardVM"
        )
        do {
            guard let result = try await service.getKanbanRuns(taskId: taskId) else {
                DMLogger.log(
                    "[TaskBoardVM] loadTaskRuns \(taskId) → null",
                    name: "TaskBoardVM"
                )
                return
            }
            let arr: [[String: Any]] = {
                if let data = result["data"] as? [[String: Any]] { return data }
                if let data = result["runs"] as? [[String: Any]] { return data }
                return []
            }()
            let runs = arr.map { TaskRun.fromJson($0, taskId: taskId) }
            let newTasks = model.tasks.map { t -> TaskItem in
                if t.id == taskId {
                    return t.updating(runHistory: runs)
                }
                return t
            }
            model = model.updating(tasks: newTasks)
            DMLogger.log(
                "[TaskBoardVM] loadTaskRuns \(taskId) → \(runs.count) runs",
                name: "TaskBoardVM"
            )
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.loadTaskRuns: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    // MARK: - Bulk Ops

    /// 批量完成任务。
    func bulkComplete(ids: [String], summary: String? = nil) async {
        guard !ids.isEmpty else { return }
        let newTasks = model.tasks.map { t -> TaskItem in
            if ids.contains(t.id) {
                return t.updating(
                    status: .done,
                    summary: summary ?? t.summary,
                    updatedAt: Date()
                )
            }
            return t
        }
        model = model.updating(tasks: newTasks)
        do {
            _ = try await service.bulkCompleteTasks(ids: ids, result: summary)
            await refresh()
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.bulkComplete: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    /// 批量归档任务。
    func bulkArchive(ids: [String]) async {
        guard !ids.isEmpty else { return }
        let newTasks = model.tasks.map { t -> TaskItem in
            if ids.contains(t.id) {
                return t.updating(status: .archived, updatedAt: Date())
            }
            return t
        }
        model = model.updating(tasks: newTasks)
        do {
            _ = try await service.bulkArchiveTasks(ids: ids)
            await refresh()
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.bulkArchive: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    /// 批量解除阻塞。
    func bulkUnblock(ids: [String]) async {
        guard !ids.isEmpty else { return }
        let newTasks = model.tasks.map { t -> TaskItem in
            if ids.contains(t.id) {
                return t.updating(status: .ready, updatedAt: Date())
            }
            return t
        }
        model = model.updating(tasks: newTasks)
        do {
            _ = try await service.bulkUnblockTasks(ids: ids)
            await refresh()
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.bulkUnblock: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    // MARK: - Board Persistence

    /// 切换活跃看板并把 slug 写入 `~/.hermes/kanban/current`(对齐官方 `boards switch`)。
    func switchBoard(_ boardId: String, persist: Bool = true) async {
        guard let board = model.boards.first(where: { $0.id == boardId }),
              !board.id.isEmpty
        else { return }

        model = model.updating(
            activeBoardId: boardId,
            isLoading: true,
            persistedActiveSlug: board.slug
        )

        do {
            if persist {
                let ok = try await service.switchBoard(slug: board.slug)
                DMLogger.log(
                    "[TaskBoardVM] switchBoard persist=\(board.slug) → \(ok)",
                    name: "TaskBoardVM"
                )
            }
            let tasks = await loadTasksForBoard(slug: board.slug)
            model = model.updating(tasks: tasks, isLoading: false)
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.switchBoard(\(boardId)): \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
            model = model.updating(isLoading: false)
        }
    }

    /// 重命名看板(写入后端,不只是本地)。
    func renameBoard(_ boardId: String, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let board = model.boards.first(where: { $0.id == boardId }) else { return }

        // 乐观更新本地
        let oldName = board.name
        model = model.updating(
            boards: model.boards.map { b in
                if b.id == boardId { return b.updating(name: trimmed) }
                return b
            }
        )

        do {
            let ok = try await service.renameBoard(slug: board.slug, newName: trimmed)
            if !ok {
                // 回滚
                model = model.updating(
                    boards: model.boards.map { b in
                        if b.id == boardId { return b.updating(name: oldName) }
                        return b
                    }
                )
                DMLogger.log(
                    "[TaskBoardVM] renameBoard \(board.slug) failed → rollback",
                    name: "TaskBoardVM"
                )
            }
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.renameBoard: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    /// 创建看板(支持 auto-switch 立即切到新看板)。
    func createBoard(
        slug: String,
        name: String,
        description: String = "",
        icon: String = "",
        autoSwitch: Bool = false
    ) async {
        guard !slug.trimmingCharacters(in: .whitespaces).isEmpty,
              !name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }

        model = model.updating(isLoading: true)
        defer { model = model.updating(isLoading: false) }

        do {
            let body: [String: Any] = [
                "slug": slug.trimmingCharacters(in: .whitespaces),
                "name": name.trimmingCharacters(in: .whitespaces),
                "description": description.trimmingCharacters(in: .whitespaces),
                "icon": icon.trimmingCharacters(in: .whitespaces),
                "autoSwitch": autoSwitch,
            ]
            if let result = try await service.createKanbanBoard(body: body) {
                let board = TaskBoard.fromJson(result)
                let boards = model.boards + [board]
                if autoSwitch {
                    model = model.updating(
                        activeBoardId: board.id,
                        boards: boards,
                        tasks: [],
                        persistedActiveSlug: board.slug
                    )
                } else {
                    model = model.updating(boards: boards)
                }
            } else {
                // Fallback: 重新拉取
                await fetchFromApi()
            }
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.createBoard API: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    /// 拉取当前 activeSlug 并与本地 activeBoardId 对齐。
    func syncActiveBoard() async {
        do {
            if let current = try await service.getCurrentBoard(),
               let curSlug = current["slug"] as? String,
               let match = model.boards.first(where: { $0.slug == curSlug })
            {
                model = model.updating(
                    activeBoardId: match.id,
                    persistedActiveSlug: curSlug
                )
            }
        } catch {
            DMLogger.error(
                "TaskBoardViewModel.syncActiveBoard: \(error.localizedDescription)",
                name: "TaskBoardVM"
            )
        }
    }

    // MARK: - Skill Sources

    /// 真实技能列表(从 SkillScannerService 扫描),供 NewTaskDialog 使用。
    func loadAvailableSkills() async -> [TBSkillItem] {
        let scanner = SkillScannerService()
        let installed = (try? scanner.scanSkills()) ?? [:]
        let optional = (try? scanner.scanOptionalSkills()) ?? [:]
        var ids = Set<String>()
        for (_, skills) in installed { for s in skills { ids.insert(s.id) } }
        for (_, skills) in optional { for s in skills { ids.insert(s.id) } }
        return ids.sorted().map { id in
            let display = SkillCatalog.displayInfo(for: id)
            return TBSkillItem(
                id: id,
                name: display?.name ?? id
            )
        }
    }
}
