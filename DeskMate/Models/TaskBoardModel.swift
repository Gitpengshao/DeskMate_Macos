import Foundation

// MARK: - Task Status

/// 任务状态（Hermes Kanban 生命周期）。
///
/// `triage → todo → ready → running → done`
///                    ↘ blocked → ready (retry) or archived`
enum TaskStatus: String, Equatable, CaseIterable, Identifiable, Codable {
    case triage
    case todo
    case ready
    case running
    case blocked
    case done
    case archived

    var id: String { rawValue }

    /// 列头显示标签。
    var label: String {
        switch self {
        case .triage:   return "Triage"
        case .todo:     return "To Do"
        case .ready:    return "Ready"
        case .running:  return "Running"
        case .blocked:  return "Blocked"
        case .done:     return "Done"
        case .archived: return "Archived"
        }
    }

    /// 列展示顺序（左→右）。
    var sortOrder: Int {
        switch self {
        case .triage:   return 0
        case .todo:     return 1
        case .ready:    return 2
        case .running:  return 3
        case .blocked:  return 4
        case .done:     return 5
        case .archived: return 6
        }
    }

    /// 解析 Hermes CLI 返回的字符串。
    static func parse(_ raw: String?) -> TaskStatus {
        switch raw {
        case "triage":   return .triage
        case "todo":     return .todo
        case "ready":    return .ready
        case "running":  return .running
        case "blocked":  return .blocked
        case "done":     return .done
        case "archived": return .archived
        default:         return .todo
        }
    }
}

// MARK: - Task Comment

/// 任务评论（agent 或 human）。
struct TaskComment: Equatable, Identifiable, Codable {
    let id: String
    let taskId: String
    let author: String
    let body: String
    let createdAt: Date

    init(
        id: String,
        taskId: String,
        author: String,
        body: String,
        createdAt: Date
    ) {
        self.id = id
        self.taskId = taskId
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }

    /// JSON 序列化。
    func toJson() -> [String: Any] {
        let iso = ISO8601DateFormatter()
        return [
            "id": id,
            "taskId": taskId,
            "author": author,
            "body": body,
            "createdAt": iso.string(from: createdAt),
        ]
    }

    /// JSON 反序列化。
    static func fromJson(_ json: [String: Any]) -> TaskComment {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateStr = json["createdAt"] as? String
        let parsedDate: Date = {
            if let s = dateStr, let d = iso.date(from: s) { return d }
            let fallback = ISO8601DateFormatter()
            if let s = dateStr, let d = fallback.date(from: s) { return d }
            return Date()
        }()
        return TaskComment(
            id: (json["id"] as? String) ?? "",
            taskId: (json["taskId"] as? String) ?? "",
            author: (json["author"] as? String) ?? "system",
            body: (json["body"] as? String) ?? "",
            createdAt: parsedDate
        )
    }
}

// MARK: - Task Link

/// 任务依赖（parent → child）。
struct TaskLink: Equatable, Codable {
    let parentId: String
    let childId: String

    init(parentId: String, childId: String) {
        self.parentId = parentId
        self.childId = childId
    }

    func toJson() -> [String: Any] {
        return ["parentId": parentId, "childId": childId]
    }

    static func fromJson(_ json: [String: Any]) -> TaskLink {
        return TaskLink(
            parentId: (json["parentId"] as? String) ?? "",
            childId: (json["childId"] as? String) ?? ""
        )
    }
}

// MARK: - Task Run

/// 任务单次运行记录 — 对齐官方 `kanban runs <id>` 数据。
///
/// 官方 `Run History` 段:
/// - outcome: `completed` / `gave_up` / `spawn_failed` / `timed_out`
/// - profile: 负责的 worker profile 名
/// - elapsed: 耗时(秒)
/// - started: 开始时间
/// - error: 失败原因(成功时为空)
/// - summary / metadata:本次 run 的 handoff 证据
struct TaskRun: Equatable, Identifiable, Codable {
    let id: String
    let taskId: String
    var outcome: String
    var profile: String
    var elapsed: Double
    var started: Date
    var error: String
    var summary: String
    var metadata: [String: String]

    init(
        id: String,
        taskId: String,
        outcome: String = "completed",
        profile: String = "",
        elapsed: Double = 0,
        started: Date = Date(),
        error: String = "",
        summary: String = "",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.taskId = taskId
        self.outcome = outcome
        self.profile = profile
        self.elapsed = elapsed
        self.started = started
        self.error = error
        self.summary = summary
        self.metadata = metadata
    }

    static func fromJson(_ json: [String: Any], taskId: String) -> TaskRun {
        let elapsed: Double = {
            if let n = json["elapsed"] as? Double { return n }
            if let n = json["elapsed"] as? Int { return Double(n) }
            return 0
        }()
        var md: [String: String] = [:]
        if let dict = json["metadata"] as? [String: Any] {
            for (k, v) in dict { md[k] = "\(v)" }
        }
        return TaskRun(
            id: (json["id"] as? String) ?? UUID().uuidString,
            taskId: taskId,
            outcome: (json["outcome"] as? String) ?? "completed",
            profile: (json["profile"] as? String) ?? "",
            elapsed: elapsed,
            started: parseDate(json["started"] ?? json["started_at"]),
            error: (json["error"] as? String) ?? "",
            summary: (json["summary"] as? String) ?? "",
            metadata: md
        )
    }

    private static func parseDate(_ value: Any?) -> Date {
        guard let value = value else { return Date() }
        if let d = value as? Date { return d }
        if let i = value as? Int { return Date(timeIntervalSince1970: TimeInterval(i)) }
        if let s = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: s) { return d }
        }
        return Date()
    }
}

// MARK: - Task Event

/// 任务事件（状态变更、指派等历史事件）。
struct TaskEvent: Equatable, Identifiable, Codable {
    let id: String
    let taskId: String
    let type: String
    let actor: String
    let note: String
    let createdAt: Date

    init(
        id: String,
        taskId: String,
        type: String,
        actor: String,
        note: String,
        createdAt: Date
    ) {
        self.id = id
        self.taskId = taskId
        self.type = type
        self.actor = actor
        self.note = note
        self.createdAt = createdAt
    }

    static func fromJson(_ json: [String: Any], taskId: String) -> TaskEvent {
        return TaskEvent(
            id: (json["id"] as? String) ?? UUID().uuidString,
            taskId: (json["task_id"] as? String) ?? (json["taskId"] as? String) ?? taskId,
            type: (json["type"] as? String) ?? (json["event"] as? String) ?? "",
            actor: (json["actor"] as? String) ?? (json["user"] as? String) ?? "system",
            note: (json["note"] as? String) ?? (json["message"] as? String) ?? "",
            createdAt: parseDate(json["createdAt"] ?? json["created_at"] ?? json["created"] ?? json["timestamp"])
        )
    }

    private static func parseDate(_ value: Any?) -> Date {
        guard let value = value else { return Date() }
        if let d = value as? Date { return d }
        if let i = value as? Int { return Date(timeIntervalSince1970: TimeInterval(i)) }
        if let s = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            let iso2 = ISO8601DateFormatter()
            if let d = iso2.date(from: s) { return d }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: s) { return d }
        }
        return Date()
    }
}

// MARK: - Task Diagnostic Log

/// 诊断日志/阻塞原因（从 `task.diagnostic` 或 `logs` 提取）。
struct TaskDiagnosticLog: Equatable, Identifiable, Codable {
    let id: String
    let taskId: String
    let reason: String
    let detail: String
    let createdAt: Date

    init(
        id: String,
        taskId: String,
        reason: String,
        detail: String,
        createdAt: Date
    ) {
        self.id = id
        self.taskId = taskId
        self.reason = reason
        self.detail = detail
        self.createdAt = createdAt
    }

    static func fromJson(_ json: [String: Any], taskId: String) -> TaskDiagnosticLog {
        return TaskDiagnosticLog(
            id: (json["id"] as? String) ?? UUID().uuidString,
            taskId: (json["task_id"] as? String) ?? (json["taskId"] as? String) ?? taskId,
            reason: (json["reason"] as? String) ?? (json["error"] as? String) ?? "",
            detail: (json["detail"] as? String) ?? (json["message"] as? String) ?? "",
            createdAt: parseDate(json["createdAt"] ?? json["created_at"] ?? json["created"] ?? json["timestamp"])
        )
    }

    private static func parseDate(_ value: Any?) -> Date {
        guard let value = value else { return Date() }
        if let d = value as? Date { return d }
        if let i = value as? Int { return Date(timeIntervalSince1970: TimeInterval(i)) }
        if let s = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            let iso2 = ISO8601DateFormatter()
            if let d = iso2.date(from: s) { return d }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: s) { return d }
        }
        return Date()
    }
}

// MARK: - Task Item

/// 任务卡片。
struct TaskItem: Equatable, Identifiable, Codable {
    let id: String
    var title: String
    var body: String
    var status: TaskStatus
    var priority: String
    var assignee: String
    var workspace: String
    var tenant: String
    var creator: String
    var idempotencyKey: String
    var parentIds: [String]
    var comments: [TaskComment]
    /// 官方 `kanban_complete --result` 字段:人类可读 closeout(独立于 assignee)
    var summary: String
    /// 官方 `kanban_complete --metadata` 字段:结构化 handoff(changed_files / tests_run 等)
    var metadata: [String: String]
    /// 官方 `kanban runs <id>` 数据:每次 attempt 一行
    var runHistory: [TaskRun]
    /// 事件流（状态变更、指派等）。
    var events: [TaskEvent]
    /// 诊断日志/阻塞原因。
    var diagnosticLogs: [TaskDiagnosticLog]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        title: String,
        body: String = "",
        status: TaskStatus,
        priority: String = "",
        assignee: String = "",
        workspace: String = "",
        tenant: String = "",
        creator: String = "",
        idempotencyKey: String = "",
        parentIds: [String] = [],
        comments: [TaskComment] = [],
        summary: String = "",
        metadata: [String: String] = [:],
        runHistory: [TaskRun] = [],
        events: [TaskEvent] = [],
        diagnosticLogs: [TaskDiagnosticLog] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.status = status
        self.priority = priority
        self.assignee = assignee
        self.workspace = workspace
        self.tenant = tenant
        self.creator = creator
        self.idempotencyKey = idempotencyKey
        self.parentIds = parentIds
        self.comments = comments
        self.summary = summary
        self.metadata = metadata
        self.runHistory = runHistory
        self.events = events
        self.diagnosticLogs = diagnosticLogs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 创建一个新任务（createdAt = updatedAt = now）。
    static func create(
        id: String,
        title: String,
        body: String = "",
        status: TaskStatus = .todo,
        priority: String = "",
        assignee: String = "",
        workspace: String = "",
        tenant: String = "",
        creator: String = "",
        idempotencyKey: String = "",
        parentIds: [String] = []
    ) -> TaskItem {
        let now = Date()
        return TaskItem(
            id: id,
            title: title,
            body: body,
            status: status,
            priority: priority,
            assignee: assignee,
            workspace: workspace,
            tenant: tenant,
            creator: creator,
            idempotencyKey: idempotencyKey,
            parentIds: parentIds,
            createdAt: now,
            updatedAt: now
        )
    }

    /// JSON 序列化。
    func toJson() -> [String: Any] {
        let iso = ISO8601DateFormatter()
        return [
            "id": id,
            "title": title,
            "body": body,
            "status": status.rawValue,
            "priority": priority,
            "assignee": assignee,
            "workspace": workspace,
            "tenant": tenant,
            "creator": creator,
            "idempotencyKey": idempotencyKey,
            "parentIds": parentIds,
            "comments": comments.map { $0.toJson() },
            "events": events.map { ["id": $0.id, "type": $0.type, "actor": $0.actor, "note": $0.note, "createdAt": iso.string(from: $0.createdAt)] },
            "diagnosticLogs": diagnosticLogs.map { ["id": $0.id, "reason": $0.reason, "detail": $0.detail, "createdAt": iso.string(from: $0.createdAt)] },
            "createdAt": iso.string(from: createdAt),
            "updatedAt": iso.string(from: updatedAt),
        ]
    }

    /// JSON 反序列化，兼容 camelCase / snake_case。
    static func fromJson(_ json: [String: Any]) -> TaskItem {
        // 解析 comments
        let commentsList: [TaskComment] = {
            if let arr = json["comments"] as? [[String: Any]] {
                return arr.map { TaskComment.fromJson($0) }
            }
            return []
        }()

        // 解析 parentIds（兼容 parent_ids）
        let parentIdsList: [String] = {
            if let arr = json["parentIds"] as? [String] { return arr }
            if let arr = json["parent_ids"] as? [String] { return arr }
            return []
        }()

        // Hermes CLI 把 priority 序列化为 int (2)，"P2" 是我们自己格式
        let rawPriority = json["priority"]
        let priorityStr: String = {
            if let i = rawPriority as? Int { return "P\(i)" }
            if let s = rawPriority as? String { return s }
            return ""
        }()

        // summary:官方 `kanban_complete --result` 字段
        let summaryStr: String = (json["summary"] as? String) ?? (json["result"] as? String) ?? ""

        // metadata:官方 `kanban_complete --metadata` JSON 对象
        var metadataMap: [String: String] = [:]
        if let dict = json["metadata"] as? [String: Any] {
            for (k, v) in dict { metadataMap[k] = "\(v)" }
        }

        // runHistory:官方 `kanban runs <id>` 数组
        let runHistoryList: [TaskRun] = {
            if let arr = json["runHistory"] as? [[String: Any]] {
                return arr.map { TaskRun.fromJson($0, taskId: (json["id"] as? String) ?? "") }
            }
            if let arr = json["runs"] as? [[String: Any]] {
                return arr.map { TaskRun.fromJson($0, taskId: (json["id"] as? String) ?? "") }
            }
            return []
        }()

        // events:状态变更/指派历史
        let taskId = (json["id"] as? String) ?? ""
        let eventsList: [TaskEvent] = {
            if let arr = json["events"] as? [[String: Any]] {
                return arr.map { TaskEvent.fromJson($0, taskId: taskId) }
            }
            if let arr = json["history"] as? [[String: Any]] {
                return arr.map { TaskEvent.fromJson($0, taskId: taskId) }
            }
            return []
        }()

        // diagnosticLogs:诊断/阻塞原因
        let diagnosticLogsList: [TaskDiagnosticLog] = {
            if let arr = json["diagnosticLogs"] as? [[String: Any]] {
                return arr.map { TaskDiagnosticLog.fromJson($0, taskId: taskId) }
            }
            if let arr = json["diagnostics"] as? [[String: Any]] {
                return arr.map { TaskDiagnosticLog.fromJson($0, taskId: taskId) }
            }
            if let dict = json["diagnostic"] as? [String: Any] {
                return [TaskDiagnosticLog.fromJson(dict, taskId: taskId)]
            }
            return []
        }()

        return TaskItem(
            id: taskId,
            title: (json["title"] as? String) ?? "",
            body: (json["body"] as? String) ?? "",
            status: TaskStatus.parse(json["status"] as? String),
            priority: priorityStr,
            assignee: (json["assignee"] as? String) ?? "",
            workspace: (json["workspace"] ?? json["workspace_kind"] ?? "") as? String ?? "",
            tenant: (json["tenant"] as? String) ?? "",
            creator: (json["creator"] as? String) ?? (json["created_by"] as? String) ?? (json["author"] as? String) ?? "",
            idempotencyKey: (json["idempotencyKey"] ?? json["idempotency_key"] ?? "") as? String ?? "",
            parentIds: parentIdsList,
            comments: commentsList,
            summary: summaryStr,
            metadata: metadataMap,
            runHistory: runHistoryList,
            events: eventsList,
            diagnosticLogs: diagnosticLogsList,
            createdAt: parseDate(json["createdAt"] ?? json["created_at"] ?? json["created"]),
            updatedAt: parseDate(
                json["updatedAt"]
                    ?? json["updated_at"]
                    ?? json["updated"]
                    ?? json["createdAt"]
                    ?? json["created_at"]
                    ?? json["created"]
            )
        )
    }

    /// 日期解析，支持 ISO 字符串、Unix 时间戳、纯日期。
    private static func parseDate(_ value: Any?) -> Date {
        guard let value = value else { return Date() }
        if let d = value as? Date { return d }
        if let i = value as? Int {
            // Hermes CLI 用秒级 Unix 时间戳
            return Date(timeIntervalSince1970: TimeInterval(i))
        }
        if let s = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            let iso2 = ISO8601DateFormatter()
            if let d = iso2.date(from: s) { return d }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: s) { return d }
            // 兼容 "2025-06-21"
            f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: s) { return d }
        }
        return Date()
    }

    /// 该任务是否可以被分发到 running（所有父任务均已完成）。
    var isReadyForDispatch: Bool {
        return status == .ready || status == .todo
    }

    /// 该任务是否处于活跃（非终止）状态。
    var isActive: Bool {
        return status != .done && status != .archived
    }

    /// 不可变更新。
    func updating(
        title: String? = nil,
        body: String? = nil,
        status: TaskStatus? = nil,
        priority: String? = nil,
        assignee: String? = nil,
        workspace: String? = nil,
        tenant: String? = nil,
        creator: String? = nil,
        idempotencyKey: String? = nil,
        parentIds: [String]? = nil,
        comments: [TaskComment]? = nil,
        summary: String? = nil,
        metadata: [String: String]? = nil,
        runHistory: [TaskRun]? = nil,
        events: [TaskEvent]? = nil,
        diagnosticLogs: [TaskDiagnosticLog]? = nil,
        updatedAt: Date? = nil
    ) -> TaskItem {
        return TaskItem(
            id: id,
            title: title ?? self.title,
            body: body ?? self.body,
            status: status ?? self.status,
            priority: priority ?? self.priority,
            assignee: assignee ?? self.assignee,
            workspace: workspace ?? self.workspace,
            tenant: tenant ?? self.tenant,
            creator: creator ?? self.creator,
            idempotencyKey: idempotencyKey ?? self.idempotencyKey,
            parentIds: parentIds ?? self.parentIds,
            comments: comments ?? self.comments,
            summary: summary ?? self.summary,
            metadata: metadata ?? self.metadata,
            runHistory: runHistory ?? self.runHistory,
            events: events ?? self.events,
            diagnosticLogs: diagnosticLogs ?? self.diagnosticLogs,
            createdAt: createdAt,
            updatedAt: updatedAt ?? Date()
        )
    }
}

// MARK: - Task Board

/// 看板（项目）。
struct TaskBoard: Equatable, Identifiable, Codable {
    let id: String
    let slug: String
    var name: String
    var description: String
    var icon: String
    var taskCount: Int
    let createdAt: Date

    init(
        id: String,
        slug: String,
        name: String,
        description: String = "",
        icon: String = "",
        taskCount: Int,
        createdAt: Date
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.description = description
        self.icon = icon
        self.taskCount = taskCount
        self.createdAt = createdAt
    }

    /// 创建一个新看板（taskCount = 0, createdAt = now）。
    static func create(
        id: String,
        slug: String,
        name: String,
        description: String = "",
        icon: String = ""
    ) -> TaskBoard {
        return TaskBoard(
            id: id,
            slug: slug,
            name: name,
            description: description,
            icon: icon,
            taskCount: 0,
            createdAt: Date()
        )
    }

    /// JSON 序列化。
    func toJson() -> [String: Any] {
        let iso = ISO8601DateFormatter()
        return [
            "id": id,
            "slug": slug,
            "name": name,
            "description": description,
            "icon": icon,
            "taskCount": taskCount,
            "createdAt": iso.string(from: createdAt),
        ]
    }

    /// JSON 反序列化，兼容 camelCase / snake_case。
    static func fromJson(_ json: [String: Any]) -> TaskBoard {
        let boardId = (json["id"] as? String) ?? (json["slug"] as? String) ?? ""
        let taskCount: Int = {
            if let i = json["taskCount"] as? Int { return i }
            if let i = json["task_count"] as? Int { return i }
            if let i = json["tasks"] as? Int { return i }
            return 0
        }()
        let createdAt: Date = {
            if let s = json["createdAt"] as? String,
               let d = ISO8601DateFormatter().date(from: s) { return d }
            if let s = json["created_at"] as? String,
               let d = ISO8601DateFormatter().date(from: s) { return d }
            if let s = json["created"] as? String,
               let d = ISO8601DateFormatter().date(from: s) { return d }
            return Date()
        }()
        return TaskBoard(
            id: boardId,
            slug: (json["slug"] as? String) ?? boardId,
            name: (json["name"] as? String) ?? (json["slug"] as? String) ?? "",
            description: (json["description"] as? String) ?? "",
            icon: (json["icon"] as? String) ?? "",
            taskCount: taskCount,
            createdAt: createdAt
        )
    }

    /// 不可变更新。
    func updating(
        slug: String? = nil,
        name: String? = nil,
        description: String? = nil,
        icon: String? = nil,
        taskCount: Int? = nil
    ) -> TaskBoard {
        return TaskBoard(
            id: id,
            slug: slug ?? self.slug,
            name: name ?? self.name,
            description: description ?? self.description,
            icon: icon ?? self.icon,
            taskCount: taskCount ?? self.taskCount,
            createdAt: createdAt
        )
    }
}

// MARK: - Page State Model

/// 任务看板页的单一状态源。
struct TaskBoardPageModel: Equatable {
    var activeBoardId: String
    var boards: [TaskBoard]
    var tasks: [TaskItem]
    var isLoading: Bool
    var errorMessage: String?

    /// 顶部筛选条件。
    var filter: TaskBoardFilter

    /// Running 列按 profile 分组。默认 true。
    var lanesByProfile: Bool

    /// 当前活跃 board 的 `~/.hermes/kanban/current` slug(若同步成功)。
    var persistedActiveSlug: String

    init(
        activeBoardId: String = "",
        boards: [TaskBoard] = [],
        tasks: [TaskItem] = [],
        isLoading: Bool = false,
        errorMessage: String? = nil,
        filter: TaskBoardFilter = TaskBoardFilter(),
        lanesByProfile: Bool = true,
        persistedActiveSlug: String = ""
    ) {
        self.activeBoardId = activeBoardId
        self.boards = boards
        self.tasks = tasks
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.filter = filter
        self.lanesByProfile = lanesByProfile
        self.persistedActiveSlug = persistedActiveSlug
    }

    // MARK: Computed

    /// 当前活跃看板。
    var activeBoard: TaskBoard? {
        if let match = boards.first(where: { $0.id == activeBoardId }) {
            return match
        }
        return boards.first
    }

    /// 当前活跃看板名称。
    var activeBoardName: String { activeBoard?.name ?? "" }

    /// 按状态分组的任务(应用 filter 后)。
    func tasksByStatus() -> [TaskStatus: [TaskItem]] {
        let filtered = applyFilter(tasks)
        var map: [TaskStatus: [TaskItem]] = [:]
        for status in TaskStatus.allCases {
            map[status] = filtered.filter { $0.status == status }
        }
        return map
    }

    /// 应用顶部筛选。
    func applyFilter(_ input: [TaskItem]) -> [TaskItem] {
        input.filter { task in
            if !filter.searchKeyword.isEmpty {
                let kw = filter.searchKeyword.lowercased()
                if !task.title.lowercased().contains(kw)
                    && !task.body.lowercased().contains(kw) {
                    return false
                }
            }
            if !filter.tenant.isEmpty, task.tenant != filter.tenant {
                return false
            }
            if !filter.assignee.isEmpty, task.assignee != filter.assignee {
                return false
            }
            return true
        }
    }

    /// 看板内 6 列:从左到右 Triage / Todo / Ready / In progress / Blocked / Done。
    static let kanbanColumns: [TaskStatus] = [
        .triage, .todo, .ready, .running, .blocked, .done,
    ]

    /// Running 列按 profile 分组(若开启)。
    func lanesByProfile(forRunning tasks: [TaskItem]) -> [(String, [TaskItem])] {
        let grouped = Dictionary(grouping: tasks, by: { $0.assignee.isEmpty ? "_unassigned" : $0.assignee })
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// 不可变更新。
    func updating(
        activeBoardId: String? = nil,
        boards: [TaskBoard]? = nil,
        tasks: [TaskItem]? = nil,
        isLoading: Bool? = nil,
        errorMessage: String? = nil,
        clearError: Bool = false,
        filter: TaskBoardFilter? = nil,
        lanesByProfile: Bool? = nil,
        persistedActiveSlug: String? = nil
    ) -> TaskBoardPageModel {
        return TaskBoardPageModel(
            activeBoardId: activeBoardId ?? self.activeBoardId,
            boards: boards ?? self.boards,
            tasks: tasks ?? self.tasks,
            isLoading: isLoading ?? self.isLoading,
            errorMessage: clearError ? nil : (errorMessage ?? self.errorMessage),
            filter: filter ?? self.filter,
            lanesByProfile: lanesByProfile ?? self.lanesByProfile,
            persistedActiveSlug: persistedActiveSlug ?? self.persistedActiveSlug
        )
    }
}

// MARK: - Filter

/// 看板筛选条件(search / tenant / assignee)。
struct TaskBoardFilter: Equatable {
    var searchKeyword: String = ""
    var tenant: String = ""
    var assignee: String = ""

    /// 当前筛选条件下是否激活。
    var isActive: Bool {
        !searchKeyword.isEmpty || !tenant.isEmpty || !assignee.isEmpty
    }
}
