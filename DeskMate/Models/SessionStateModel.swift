import Foundation

/// 会话列表项 — 对齐 Flutter `SessionRow`，与 Hermes Gateway `/api/sessions` 字段一致。
struct SessionRow: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let source: String
    let messageCount: Int
    let model: String
    let startedAt: String
    let endedAt: String
    let lastActive: String
    var preview: String = ""
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var assistantPreview: String = ""

    /// 从后端 JSON 解析单条会话。
    init(from json: [String: Any]) {
        self.id = Self.string(json["id"])
        self.title = Self.string(json["title"])
        self.source = Self.string(json["source"])
        self.messageCount = Self.int(json["message_count"])
        self.model = Self.string(json["model"])
        self.startedAt = Self.string(json["started_at"])
        self.endedAt = Self.string(json["ended_at"])
        self.lastActive = Self.string(json["last_active"])
        self.preview = Self.string(json["preview"])
        self.inputTokens = Self.int(json["input_tokens"])
        self.outputTokens = Self.int(json["output_tokens"])
        self.assistantPreview = Self.string(json["assistant_preview"])
    }

    init(
        id: String,
        title: String,
        source: String,
        messageCount: Int,
        model: String,
        startedAt: String,
        endedAt: String,
        lastActive: String,
        preview: String = "",
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        assistantPreview: String = ""
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.messageCount = messageCount
        self.model = model
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lastActive = lastActive
        self.preview = preview
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.assistantPreview = assistantPreview
    }

    private static func string(_ value: Any?) -> String {
        guard let v = value else { return "" }
        if let s = v as? String { return s }
        return String(describing: v)
    }

    private static func int(_ value: Any?) -> Int {
        guard let v = value else { return 0 }
        if let n = v as? Int { return n }
        if let n = v as? NSNumber { return n.intValue }
        if let n = v as? Double { return Int(n) }
        return 0
    }
}

/// 会话侧边栏整体状态 — 对齐 Flutter `SessionStateModel`。
struct SessionStateModel: Equatable {
    var sessions: [SessionRow] = []
    var searchQuery: String = ""
    var isLoading: Bool = false
    var errorMessage: String?

    /// 根据搜索词过滤后的会话列表（标题/模型/助手预览任意包含即命中）。
    var filteredSessions: [SessionRow] {
        guard !searchQuery.isEmpty else { return sessions }
        let q = searchQuery.lowercased()
        return sessions.filter { row in
            row.title.lowercased().contains(q)
                || row.model.lowercased().contains(q)
                || row.assistantPreview.lowercased().contains(q)
        }
    }
}
