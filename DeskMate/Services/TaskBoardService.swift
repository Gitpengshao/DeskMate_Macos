import Foundation

/// 任务看板服务 — 封装 `hermes kanban ...` CLI 调用。
///
/// 严格对齐 Flutter `HermesService.getKanbanBoards / getKanbanTasks /
/// createKanbanBoard / deleteKanbanBoard / createKanbanTask /
/// updateKanbanTask / addKanbanComment / createKanbanLink`：
///
/// - Hermes Gateway **不**暴露 Kanban REST 端点，所有读写都走 `hermes kanban` CLI
/// - 优先解析 `--json` 结构化输出；fallback 解析文本表格
/// - boards 列表在 CLI 失败时还能从 `~/.hermes/kanban/boards/<slug>/` 文件系统兜底扫描
///
/// 与 `SkillInstallService` 一样以 `nonisolated` 异步子进程方式执行；
/// ViewModel 在 `@MainActor` 上聚合结果。
nonisolated final class TaskBoardService {

    /// 单例 — UI 多次调用共享同一份 CLI 路径解析。
    static let shared = TaskBoardService()

    /// 默认 CLI 超时（秒）。`list/show` 等查询给 10s，写操作给 30s。
    private let queryTimeout: TimeInterval = 10
    private let writeTimeout: TimeInterval = 30

    /// 最近一次失败的原始 stderr（供 UI 展示）。
    private(set) var lastError: String?

    private init() {}

    // MARK: - Public API

    // ---- Boards ----

    /// 列出所有看板 — 对齐 Flutter `getKanbanBoards`。
    ///
    /// 策略 1: `hermes kanban boards list --json`
    /// 策略 2: 解析 CLI 表格输出
    /// 策略 3: 文件系统兜底扫描 `~/.hermes/kanban/boards/<slug>/`
    func getKanbanBoards() async -> [[String: Any]]? {
        DMLogger.log("[getKanbanBoards] START", name: "TaskBoardService")

        // Strategy 1: --json
        let result = await runKanbanCli(args: ["boards", "list", "--json"])
        DMLogger.log(
            "[getKanbanBoards] result type=\(type(of: result)), isList=\(result is [Any])",
            name: "TaskBoardService"
        )

        if let list = result as? [[String: Any]] {
            DMLogger.log(
                "[getKanbanBoards] Strategy1(JSON) SUCCESS → \(list.count) boards",
                name: "TaskBoardService"
            )
            return list
        }
        // JSON 返回单层数组（元素本身是 [String: Any]）
        if let arr = result as? [Any] {
            let casted = arr.compactMap { $0 as? [String: Any] }
            if !casted.isEmpty {
                DMLogger.log(
                    "[getKanbanBoards] Strategy1(JSON) SUCCESS(cast) → \(casted.count) boards",
                    name: "TaskBoardService"
                )
                return casted
            }
        }

        // Strategy 2: table output
        if let tableStr = result as? String {
            let parsed = parseTableOutput(tableStr)
            if !parsed.isEmpty {
                DMLogger.log(
                    "[getKanbanBoards] Strategy2(TABLE) → \(parsed.count) rows",
                    name: "TaskBoardService"
                )
                return parsed.map { row in
                    var dict: [String: Any] = [:]
                    for (k, v) in row { dict[k] = v }
                    return dict
                }
            }
        }

        // Strategy 3: filesystem fallback
        DMLogger.log(
            "[getKanbanBoards] Strategy3(FILESYSTEM) fallback",
            name: "TaskBoardService"
        )
        return listBoardsFromFilesystem()
    }

    /// 创建看板 — 对齐 Flutter `createKanbanBoard`。
    ///
    /// 运行 `hermes kanban boards create <slug> --name <name> [--description ...] [--icon ...] [--switch]`
    /// 然后重新拉取列表以拿到真实数据。
    func createKanbanBoard(body: [String: Any]) async -> [String: Any]? {
        guard let slug = body["slug"] as? String, !slug.isEmpty,
              let name = body["name"] as? String, !name.isEmpty
        else { return nil }

        // 客户端 slug 校验：1-64 字符、小写字母数字 + 连字符/下划线、必须字母数字开头
        guard Self.validateSlug(slug) else {
            DMLogger.error(
                "[createKanbanBoard] slug invalid: \(slug)",
                name: "TaskBoardService"
            )
            return nil
        }

        var args: [String] = ["boards", "create", slug, "--name", name]
        if let desc = body["description"] as? String, !desc.isEmpty {
            args.append(contentsOf: ["--description", desc])
        }
        if let icon = body["icon"] as? String, !icon.isEmpty {
            args.append(contentsOf: ["--icon", icon])
        }
        if let autoSwitch = body["autoSwitch"] as? Bool, autoSwitch {
            args.append("--switch")
        }
        await runKanbanCli(args: args, timeout: writeTimeout)

        // Re-fetch to find the created board.
        if let boards = await getKanbanBoards() {
            return boards.first(where: { ($0["slug"] as? String) == slug })
        }
        return nil
    }

    /// 切换当前活跃看板(写 `~/.hermes/kanban/current`) — 对齐官方 `boards switch`。
    @discardableResult
    func switchBoard(slug: String) async -> Bool {
        let result = await runKanbanCli(
            args: ["boards", "switch", slug],
            timeout: writeTimeout
        )
        return result != nil
    }

    /// 重命名看板(只改 display name,slug 不可变) — 对齐官方 `boards rename`。
    @discardableResult
    func renameBoard(slug: String, newName: String) async -> Bool {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let result = await runKanbanCli(
            args: ["boards", "rename", slug, newName],
            timeout: writeTimeout
        )
        return result != nil
    }

    /// 获取当前活跃看板 — 对齐官方 `boards show`。
    func getCurrentBoard() async -> [String: Any]? {
        let result = await runKanbanCli(
            args: ["boards", "show", "--json"],
            timeout: queryTimeout
        )
        if let dict = result as? [String: Any] { return dict }
        if let arr = result as? [Any], let first = arr.first as? [String: Any] {
            return first
        }
        return nil
    }

    /// Slug 校验 — 对齐官方 `kanban/boards.py:validate_slug`。
    /// 规则:`[a-z0-9_-]+`,1-64 字符,首字符必须为字母数字。
    static func validateSlug(_ slug: String) -> Bool {
        guard !slug.isEmpty, slug.count <= 64 else { return false }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "-_"))
        let first = slug.unicodeScalars.first!
        guard CharacterSet.lowercaseLetters.contains(first)
                || CharacterSet.decimalDigits.contains(first)
        else { return false }
        return slug.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// 删除（归档）看板 — 对齐 Flutter `deleteKanbanBoard`。
    @discardableResult
    func deleteKanbanBoard(slug: String) async -> Bool {
        await runKanbanCli(args: ["boards", "rm", slug], timeout: writeTimeout)
        if let boards = await getKanbanBoards() {
            return !boards.contains(where: { ($0["slug"] as? String) == slug })
        }
        return true
    }

    // ---- Tasks ----

    /// 列出某看板的所有任务 — 对齐 Flutter `getKanbanTasks`。
    ///
    /// 返回 `{ "data": [Task, ...] }` 的结构，兼容 Flutter 端调用方。
    func getKanbanTasks(boardSlug: String) async -> [String: Any]? {
        DMLogger.log(
            "[getKanbanTasks] START boardSlug=\"\(boardSlug)\"",
            name: "TaskBoardService"
        )

        let result = await runKanbanCli(
            args: ["list", "--json"],
            boardSlug: boardSlug
        )

        if let arr = result as? [[String: Any]] {
            DMLogger.log(
                "[getKanbanTasks] JSON list → \(arr.count) tasks",
                name: "TaskBoardService"
            )
            return ["data": arr]
        }
        if let arr = result as? [Any] {
            let casted = arr.compactMap { $0 as? [String: Any] }
            if !casted.isEmpty {
                return ["data": casted]
            }
        }
        if let tableStr = result as? String {
            let parsed = parseTableOutput(tableStr)
            if !parsed.isEmpty {
                let dicts = parsed.map { row -> [String: Any] in
                    var dict: [String: Any] = [:]
                    for (k, v) in row { dict[k] = v }
                    return dict
                }
                return ["data": dicts]
            }
        }
        DMLogger.log(
            "[getKanbanTasks] returning NULL (no data found for board=\"\(boardSlug)\")",
            name: "TaskBoardService"
        )
        return nil
    }

    /// 创建任务 — 对齐 Flutter `createKanbanTask`。
    ///
    /// 运行 `hermes kanban create <title> --json ...` 并解析返回值。
    /// 失败时回退到重新拉取任务列表按 title 匹配。
    func createKanbanTask(body: [String: Any]) async -> [String: Any]? {
        guard let title = body["title"] as? String, !title.isEmpty else { return nil }

        var args: [String] = ["create", title, "--json"]
        let board = body["_board"] as? String

        if let assignee = body["assignee"] as? String, !assignee.isEmpty {
            args.append(contentsOf: ["--assignee", assignee])
        }
        if let taskBody = body["body"] as? String, !taskBody.isEmpty {
            args.append(contentsOf: ["--body", taskBody])
        }
        if let priority = body["priority"] as? String, !priority.isEmpty {
            if let numeric = parseNumericPriority(priority) {
                args.append(contentsOf: ["--priority", "\(numeric)"])
            }
        }
        // CLI --initial-status 仅支持 {blocked, running}；"todo" 是默认，不要传
        if let status = body["status"] as? String,
           !status.isEmpty, status != "todo" {
            args.append(contentsOf: ["--initial-status", status])
        }
        if let workspace = body["workspace"] as? String, !workspace.isEmpty {
            // 官方 workspace 规则:
            // - 绝对路径 → 加 `dir:` 前缀
            // - `scratch` / `worktree` → 关键字直传
            // - 相对路径(如 `./foo` / `../foo`)→ 拒绝(confused-deputy)
            let ws: String
            if workspace == "scratch" || workspace == "worktree" {
                ws = workspace
            } else if workspace.hasPrefix("/") {
                ws = "dir:\(workspace)"
            } else if workspace.hasPrefix("dir:") || workspace.hasPrefix("worktree:") {
                ws = workspace
            } else {
                DMLogger.error(
                    "[createKanbanTask] workspace 相对路径被拒绝: \(workspace)",
                    name: "TaskBoardService"
                )
                return nil
            }
            args.append(contentsOf: ["--workspace", ws])
        }
        if let tenant = body["tenant"] as? String, !tenant.isEmpty {
            args.append(contentsOf: ["--tenant", tenant])
        }
        if let idempotencyKey = body["idempotencyKey"] as? String,
           !idempotencyKey.isEmpty {
            args.append(contentsOf: ["--idempotency-key", idempotencyKey])
        }
        if let branch = body["branch"] as? String, !branch.isEmpty {
            args.append(contentsOf: ["--branch", branch])
        }
        if let skills = body["skills"] as? [String], !skills.isEmpty {
            for s in skills {
                args.append(contentsOf: ["--skill", s])
            }
        }
        if let maxRetries = body["maxRetries"] as? Int {
            args.append(contentsOf: ["--max-retries", "\(maxRetries)"])
        }
        // --parent 单值:多 parent 时仅取首个,其余需后续 link 补链(官方 CLI 单值约束)
        if let parentIds = body["parentIds"] as? [String], let firstParent = parentIds.first {
            args.append(contentsOf: ["--parent", firstParent])
            if parentIds.count > 1 {
                DMLogger.log(
                    "[createKanbanTask] 多 parent 仅取首个 \(firstParent),其余 \(parentIds.count - 1) 个需后续 link 补链",
                    name: "TaskBoardService"
                )
            }
        }

        DMLogger.log(
            "[createKanbanTask] CLI args: \(args)",
            name: "TaskBoardService"
        )
        let result = await runKanbanCli(args: args, boardSlug: board, timeout: writeTimeout)
        DMLogger.log(
            "[createKanbanTask] result type=\(type(of: result))",
            name: "TaskBoardService"
        )

        if let dict = result as? [String: Any] {
            DMLogger.log(
                "[createKanbanTask] SUCCESS (JSON returned task directly)",
                name: "TaskBoardService"
            )
            return dict
        }

        // Fallback: re-fetch task list and find by title.
        let activeBoard = board ?? "default"
        if let tasksResp = await getKanbanTasks(boardSlug: activeBoard),
           let data = tasksResp["data"] as? [Any] {
            for case let t as [String: Any] in data {
                if (t["title"] as? String) == title {
                    DMLogger.log(
                        "[createKanbanTask] found by re-fetch: id=\(t["id"] ?? "?")",
                        name: "TaskBoardService"
                    )
                    return t
                }
            }
        }
        DMLogger.log(
            "[createKanbanTask] FAILED — returning null",
            name: "TaskBoardService"
        )
        return nil
    }

    /// 更新任务（status 切换 / 字段编辑） — 对齐官方 `kanban` CLI verb。
    ///
    /// 状态变更走 `hermes kanban <verb> <taskId>`:
    /// - `done`      → `complete <id> --result <summary> [--metadata <json>]`
    /// - `blocked`   → `block <id> <reason>` (reason 透传,不能写死)
    /// - `ready`     → `unblock <id>`
    /// - `archived`  → `archive <id>`
    /// - 其它状态    → `move <id> <status>`
    ///
    /// 批量操作:同一 verb 接受多个 id(`complete / archive / unblock`),
    /// 配合 `--ids` / positional 多值。block 接受单 id + reason + `--ids <more>`。
    @discardableResult
    func updateKanbanTask(
        taskId: String,
        body: [String: Any]
    ) async -> Bool {
        guard let status = body["status"] as? String else {
            // title / body / assignee / priority / workspace / tenant 字段
            // Hermes CLI 当前不直接支持,仍以成功返回(对齐 Flutter 行为)
            DMLogger.log(
                "[updateKanbanTask] non-status update for \(taskId) (CLI unsupported) → noop",
                name: "TaskBoardService"
            )
            return true
        }

        var verb: String
        var extraArgs: [String] = []
        switch status {
        case "done":
            verb = "complete"
            // 官方:`complete <id> [id2...] --result <summary> [--metadata <json>]`
            // summary 和 metadata 是两个独立字段,不能混到 assignee
            if let summary = body["summary"] as? String, !summary.isEmpty {
                extraArgs.append(contentsOf: ["--result", summary])
            }
            if let metadata = body["metadata"] as? [String: Any], !metadata.isEmpty,
               let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                extraArgs.append(contentsOf: ["--metadata", jsonStr])
            }
        case "blocked":
            verb = "block"
            // 官方:`block <id> "reason"`,reason 必填且必须透传
            if let reason = body["reason"] as? String, !reason.isEmpty {
                extraArgs = [reason]
            } else {
                DMLogger.error(
                    "[updateKanbanTask] block 缺少 reason → refused",
                    name: "TaskBoardService"
                )
                return false
            }
        case "ready":
            verb = "unblock"
        case "archived":
            verb = "archive"
        default:
            // 官方 Hermes Kanban CLI **没有** `move` verb。
            // 合法的状态变更只有:complete(done) / block(blocked) / unblock(ready) /
            // archive(archived) / specify(triage→todo) / decompose(triage→子任务)。
            // running 由 dispatcher claim 后自动进入,triage/todo 也无直接 verb。
            // 任何其它目标状态都拒绝,避免调用不存在的命令。
            DMLogger.error(
                "[updateKanbanTask] 拒绝非官方状态转换: status=\(status) (无对应 CLI verb)",
                name: "TaskBoardService"
            )
            return false
        }
        let result = await runKanbanCli(
            args: [verb, taskId] + extraArgs,
            timeout: writeTimeout
        )
        if let dict = result as? [String: Any], dict["error"] != nil {
            return false
        }
        return result != nil
    }

    /// 批量完成任务 — 对齐官方 `complete <id1> <id2> --result "..."`。
    @discardableResult
    func bulkCompleteTasks(
        ids: [String],
        result: String? = nil
    ) async -> Bool {
        guard !ids.isEmpty else { return false }
        var args: [String] = ["complete"] + ids
        if let result = result, !result.isEmpty {
            args.append(contentsOf: ["--result", result])
        }
        let out = await runKanbanCli(args: args, timeout: writeTimeout)
        return out != nil
    }

    /// 批量归档 — 对齐官方 `archive <id1> <id2> ...`。
    @discardableResult
    func bulkArchiveTasks(ids: [String]) async -> Bool {
        guard !ids.isEmpty else { return false }
        let out = await runKanbanCli(
            args: ["archive"] + ids,
            timeout: writeTimeout
        )
        return out != nil
    }

    /// 批量解除阻塞 — 对齐官方 `unblock <id1> <id2> ...`。
    @discardableResult
    func bulkUnblockTasks(ids: [String]) async -> Bool {
        guard !ids.isEmpty else { return false }
        let out = await runKanbanCli(
            args: ["unblock"] + ids,
            timeout: writeTimeout
        )
        return out != nil
    }

    /// 拉取任务运行历史 — 对齐官方 `kanban runs <id>`。
    func getKanbanRuns(taskId: String) async -> [String: Any]? {
        let result = await runKanbanCli(
            args: ["runs", taskId, "--json"],
            timeout: queryTimeout
        )
        if let dict = result as? [String: Any] { return dict }
        if let arr = result as? [Any] { return ["data": arr] }
        return nil
    }

    /// 拉取看板统计 — 对齐官方 `kanban stats`。
    func getKanbanStats() async -> [String: Any]? {
        let result = await runKanbanCli(
            args: ["stats", "--json"],
            timeout: queryTimeout
        )
        if let dict = result as? [String: Any] { return dict }
        return nil
    }

    /// 拉取单任务完整详情 — 对齐官方 `kanban show <id>`(含 worker_context)。
    func getKanbanShow(taskId: String) async -> [String: Any]? {
        let result = await runKanbanCli(
            args: ["show", taskId, "--json"],
            timeout: queryTimeout
        )
        if let dict = result as? [String: Any] { return dict }
        return nil
    }

    /// 手动分解 Triage 任务为子任务 — 对齐官方 `kanban decompose <id>`。
    @discardableResult
    func decomposeTask(taskId: String) async -> Bool {
        let out = await runKanbanCli(
            args: ["decompose", taskId],
            timeout: writeTimeout
        )
        return out != nil
    }

    /// 把 Triage 任务的粗想法展开为完整 spec(goal / approach / acceptance criteria)
    /// 并提升到 `todo` — 对齐官方 `kanban specify <id>`(使用 `auxiliary.triage_specifier`)。
    ///
    /// 注意:官方语义是 triage → todo,**不是** → ready。
    /// 批量变体 `specify --all --tenant X` 见 `specifyAllTasks(tenant:)`。
    @discardableResult
    func specifyTask(taskId: String) async -> Bool {
        let out = await runKanbanCli(
            args: ["specify", taskId],
            timeout: writeTimeout
        )
        return out != nil
    }

    /// 批量为某 tenant 下所有 Triage 任务跑 specify — 对齐官方
    /// `kanban specify --all --tenant <tenant>`。
    @discardableResult
    func specifyAllTasks(tenant: String? = nil) async -> Bool {
        var args: [String] = ["specify", "--all"]
        if let tenant = tenant, !tenant.isEmpty {
            args.append(contentsOf: ["--tenant", tenant])
        }
        let out = await runKanbanCli(args: args, timeout: writeTimeout)
        return out != nil
    }

    /// 立即触发一次 dispatcher tick — 对齐官方 nudge 操作。
    @discardableResult
    func nudgeDispatcher() async -> Bool {
        let out = await runKanbanCli(
            args: ["dispatch"],
            timeout: queryTimeout
        )
        return out != nil
    }

    /// 添加评论 — 对齐 Flutter `addKanbanComment`。
    @discardableResult
    func addKanbanComment(
        taskId: String,
        body: [String: Any]
    ) async -> [String: Any]? {
        guard let bodyText = body["body"] as? String, !bodyText.isEmpty else { return nil }
        let result = await runKanbanCli(
            args: ["comment", taskId, bodyText, "--json"],
            timeout: writeTimeout
        )
        return result as? [String: Any]
    }

    /// 创建任务依赖（parent → child） — 对齐 Flutter `createKanbanLink`。
    @discardableResult
    func createKanbanLink(body: [String: Any]) async -> [String: Any]? {
        // Flutter 端使用 snake_case，与 CLI --parent-id / --child-id 命名一致
        let parentId = (body["parent_id"] as? String) ?? (body["parentId"] as? String) ?? ""
        let childId = (body["child_id"] as? String) ?? (body["childId"] as? String) ?? ""
        guard !parentId.isEmpty, !childId.isEmpty else { return nil }

        let result = await runKanbanCli(
            args: ["link", parentId, childId, "--json"],
            timeout: writeTimeout
        )
        return result as? [String: Any]
    }

    // MARK: - Process

    /// 执行 `hermes kanban <args>` 子进程。
    private func runKanbanCli(
        args: [String],
        boardSlug: String? = nil,
        timeout: TimeInterval? = nil
    ) async -> Any? {
        let hermesHome = AppConstants.resolveHermesHome()
        let hermesBin = (hermesHome as NSString)
            .appendingPathComponent("hermes-agent/venv/bin/hermes")
        let fm = FileManager.default
        let executable: String
        if fm.isExecutableFile(atPath: hermesBin) {
            executable = hermesBin
        } else {
            // Fallback: ~/.local/bin/hermes
            let fallback = (NSHomeDirectory() as NSString)
                .appendingPathComponent(".local/bin/hermes")
            if fm.isExecutableFile(atPath: fallback) {
                executable = fallback
            } else {
                DMLogger.error(
                    "runKanbanCli: hermes CLI 未找到: \(hermesBin)",
                    name: "TaskBoardService"
                )
                lastError = "hermes CLI 未找到: \(hermesBin)"
                return nil
            }
        }

        var fullArgs: [String] = ["kanban"]
        if let slug = boardSlug, !slug.isEmpty {
            fullArgs.append(contentsOf: ["--board", slug])
        }
        fullArgs.append(contentsOf: args)

        DMLogger.log(
            "runKanbanCli: \(executable) \(fullArgs.joined(separator: " "))",
            name: "TaskBoardService"
        )

        let result = await runProcess(
            executable: executable,
            args: fullArgs,
            timeout: timeout ?? queryTimeout,
            cwd: hermesHome
        )
        if !result.success {
            DMLogger.error(
                "runKanbanCli: exit=\(result.exitCode), stderr=\(result.stderr)",
                name: "TaskBoardService"
            )
            lastError = result.stderr.isEmpty ? result.stdout : result.stderr
            return nil
        }
        lastError = nil

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if stdout.isEmpty {
            DMLogger.log(
                "runKanbanCli: stdout empty",
                name: "TaskBoardService"
            )
            return nil
        }

        // 1) 尝试 JSON 解析
        if let data = stdout.data(using: .utf8) {
            if let any = try? JSONSerialization.jsonObject(with: data) {
                DMLogger.log(
                    "runKanbanCli: JSON parsed type=\(type(of: any))",
                    name: "TaskBoardService"
                )
                return any
            }
        }

        // 2) Fallback: 原始字符串（表格输出）
        DMLogger.log(
            "runKanbanCli: not JSON, returning raw string (\(stdout.count) chars)",
            name: "TaskBoardService"
        )
        return stdout
    }

    /// 通用子进程执行（异步 + 超时）— 复用 SkillInstallService 的实现模式。
    private func runProcess(
        executable: String,
        args: [String],
        timeout: TimeInterval,
        cwd: String? = nil
    ) async -> ShellResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ShellResult, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.environment = ProcessInfo.processInfo.environment
            if let cwd = cwd, !cwd.isEmpty {
                process.currentDirectoryPath = cwd
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let lock = NSLock()
            var didResume = false

            func resume(_ result: ShellResult) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                cont.resume(returning: result)
            }

            process.terminationHandler = { proc in
                let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                let ok = proc.terminationStatus == 0
                resume(ShellResult(
                    success: ok,
                    exitCode: proc.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                ))
            }

            do {
                try process.run()
            } catch {
                resume(ShellResult(
                    success: false,
                    exitCode: -1,
                    stdout: "",
                    stderr: "process.run failed: \(error.localizedDescription)"
                ))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    DMLogger.error(
                        "runProcess: timeout (\(timeout)s), killing pid=\(process.processIdentifier)",
                        name: "TaskBoardService"
                    )
                    kill(process.processIdentifier, SIGTERM)
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// 解析 CLI 表格输出 — 对齐 Flutter `_parseTableOutput`。
    ///
    /// Hermes 表格样例：
    /// ```
    /// SLUG       NAME      DESCRIPTION   TASKS  CREATED
    /// default    Default   Default board 3      2025-06-21
    /// ```
    private func parseTableOutput(_ output: String) -> [[String: String]] {
        let lines = output.split(separator: "\n").map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return [] }

        let header = lines[0]
        // 找列起始位置
        var colStarts: [Int] = []
        var inSpace = true
        for (i, ch) in header.enumerated() {
            if ch != " " && inSpace {
                colStarts.append(i)
                inSpace = false
            } else if ch == " " {
                inSpace = true
            }
        }
        guard !colStarts.isEmpty else { return [] }

        // 列名
        let colEnds: [Int] = Array(colStarts.dropFirst()) + [header.count]
        let headers: [String] = (0..<colStarts.count).map { c in
            let start = colStarts[c]
            let end = colEnds[c]
            let startIdx = header.index(header.startIndex, offsetBy: start)
            let endIdx = header.index(header.startIndex, offsetBy: min(end, header.count))
            return header[startIdx..<endIdx]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
        }

        var rows: [[String: String]] = []
        for r in 1..<lines.count {
            let line = lines[r]
            var row: [String: String] = [:]
            for c in 0..<headers.count {
                let start = colStarts[c]
                let end: Int = (c + 1 < colStarts.count) ? colStarts[c + 1] : line.count
                if start < line.count {
                    let valEnd = min(end, line.count)
                    let startIdx = line.index(line.startIndex, offsetBy: start)
                    let valEndIdx = line.index(line.startIndex, offsetBy: valEnd)
                    let value = String(line[startIdx..<valEndIdx])
                        .trimmingCharacters(in: .whitespaces)
                    row[headers[c]] = value
                } else {
                    row[headers[c]] = ""
                }
            }
            // 跳过纯分隔行（"─────"）
            if row.values.allSatisfy({ $0.isEmpty || $0.contains("─") }) {
                continue
            }
            rows.append(row)
        }
        return rows
    }

    /// 把 "P1"/"P2" 转换成 int — 对齐 Flutter `_parseNumericPriority`。
    private func parseNumericPriority(_ priority: String) -> Int? {
        var stripped = priority
        if stripped.hasPrefix("P") || stripped.hasPrefix("p") {
            stripped = String(stripped.dropFirst())
        }
        return Int(stripped.trimmingCharacters(in: .whitespaces))
    }

    /// 从文件系统兜底扫描看板 — 对齐 Flutter `_listBoardsFromFilesystem`。
    private func listBoardsFromFilesystem() -> [[String: Any]]? {
        let hermesHome = AppConstants.resolveHermesHome()
        let fm = FileManager.default
        var boards: [[String: Any]] = []

        // Default board: ~/.hermes/kanban.db
        let defaultDb = (hermesHome as NSString).appendingPathComponent("kanban.db")
        if fm.fileExists(atPath: defaultDb) {
            boards.append([
                "slug": "default",
                "name": "Default",
                "description": "",
                "icon": "",
                "task_count": 0,
            ])
        }

        // Named boards: ~/.hermes/kanban/boards/<slug>/
        let kanbanDir = (hermesHome as NSString).appendingPathComponent("kanban")
        let boardsDir = (kanbanDir as NSString).appendingPathComponent("boards")
        if let contents = try? fm.contentsOfDirectory(atPath: boardsDir) {
            for slug in contents {
                if slug.hasPrefix("_") { continue }
                let dbFile = (boardsDir as NSString)
                    .appendingPathComponent("\(slug)/kanban.db")
                if fm.fileExists(atPath: dbFile) {
                    boards.append([
                        "slug": slug,
                        "name": slug,
                        "description": "",
                        "icon": "",
                        "task_count": 0,
                    ])
                }
            }
        }

        if !boards.isEmpty {
            DMLogger.log(
                "Kanban FS: found \(boards.count) boards",
                name: "TaskBoardService"
            )
        }
        return boards.isEmpty ? nil : boards
    }
}
