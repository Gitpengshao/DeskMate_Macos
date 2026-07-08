import Foundation

/// Gateway 流式事件 — 对齐 Flutter `GatewayStreamEvent`。
struct GatewayStreamEvent {
    /// 自定义事件名（`event:` 行）。`nil` 表示标准 OpenAI SSE data 行。
    let event: String?
    /// `data:` 行原始内容。
    let data: String?
    /// `id:` 行（目前未使用，仅为兼容）。
    let id: String?

    /// 尝试将 data 解析为 JSON 字典；非 JSON 时返回 nil。
    var dataAsJson: [String: Any]? {
        guard let data = data, !data.isEmpty else { return nil }
        guard let d = data.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
}

/// SSE 流包装 — 对齐 Flutter `GatewaySseStream`。
///
/// 通过 `URLSession.bytes` 持续读取响应体并按 SSE 块解析；
/// 取消时关闭底层 task。
final class GatewaySseStream {
    let events: AsyncStream<GatewayStreamEvent>
    let statusCode: Int
    /// 后端分配的 sessionId（来自 `X-Hermes-Session-Id` 响应头）。
    let sessionId: String?
    /// 非 200 时累积的响应体原文（最多 4KB），用于把上游错误回传给 UI。
    let errorBody: String?

    private var continuation: AsyncStream<GatewayStreamEvent>.Continuation?
    private weak var task: URLSessionTask?

    init(
        events: AsyncStream<GatewayStreamEvent>,
        continuation: AsyncStream<GatewayStreamEvent>.Continuation?,
        statusCode: Int,
        sessionId: String?,
        task: URLSessionTask?,
        errorBody: String? = nil
    ) {
        self.events = events
        self.continuation = continuation
        self.statusCode = statusCode
        self.sessionId = sessionId
        self.task = task
        self.errorBody = errorBody
    }

    /// 取消流（与 Flutter `GatewaySseStream.cancel()` 等价）。
    func cancel() {
        task?.cancel()
        continuation?.finish()
        continuation = nil
    }
}

/// OpenAI 兼容的多模态内容片段。
enum ChatContentPart: Encodable {
    case text(String)
    case imageUrl(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageUrl(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageUrl(url: url), forKey: .imageUrl)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, text
        case imageUrl = "image_url"
    }

    private struct ImageUrl: Encodable {
        let url: String
    }
}

/// 单条 Chat Completion 消息 — 对齐 Flutter `ChatMessage`（gateway 客户端版本）。
///
/// `content` 支持纯文本（assistant/system/tool）或多模态数组（user 视觉消息）。
struct GatewayChatMessage: Encodable {
    let role: String
    let content: GatewayChatMessageContent

    /// 便捷构造纯文本消息。
    init(role: String, content: String) {
        self.role = role
        self.content = .text(content)
    }

    /// 便捷构造多模态消息（文本 + 图片）。
    init(role: String, parts: [ChatContentPart]) {
        self.role = role
        self.content = .parts(parts)
    }

    /// 用于日志/调试的纯文本近似长度（多模态消息只统计文本部分）。
    var contentText: String {
        switch content {
        case .text(let string): return string
        case .parts(let parts):
            return parts.compactMap {
                if case .text(let t) = $0 { return t }
                return nil
            }.joined()
        }
    }
}

/// Gateway 消息内容 — 纯文本或多模态数组。
enum GatewayChatMessageContent: Encodable {
    case text(String)
    case parts([ChatContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

/// Chat Completion 请求体 — 对齐 Flutter `ChatCompletionRequest`。
///
/// 字段：
/// - `model` / `messages` / `stream` / `session_id`：与 OpenAI Chat Completions 兼容
/// - `reasoning_effort`：对齐 Hermes 官方
///   [`agent.reasoning_effort`](https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/configuration#%E6%8E%A8%E7%90%86%E5%8A%AA%E5%8A%9B%E7%A8%8B%E5%BA%A6)
///   — 单次请求级别覆盖（`none` | `low` | `minimal` | `medium` | `high` | `xhigh`）
struct ChatCompletionRequest: Encodable {
    let messages: [GatewayChatMessage]
    let model: String
    let stream: Bool
    let sessionId: String?
    let reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case messages, model, stream
        case sessionId = "session_id"
        case reasoningEffort = "reasoning_effort"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(messages, forKey: .messages)
        try c.encode(model, forKey: .model)
        try c.encode(stream, forKey: .stream)
        // 仅在 sessionId 非空时写入，避免序列化空字符串。
        if let sid = sessionId, !sid.isEmpty {
            try c.encode(sid, forKey: .sessionId)
        }
        // 仅在 reasoningEffort 非空时写入（保持向后兼容）。
        if let effort = reasoningEffort, !effort.isEmpty {
            try c.encode(effort, forKey: .reasoningEffort)
        }
    }
}

/// Hermes Gateway HTTP 客户端 — 对齐 Flutter `GatewayClient`。
///
/// 封装健康检查、会话列表/删除、会话消息查询、SSE 流式 Chat。
final class GatewayClient {

    /// 全局共享实例 — Hermes Gateway 启动后由 `HermesGatewayService` 注入 apiKey。
    static let shared = GatewayClient()

    private let host: String
    private let port: Int
    /// API 鉴权 key；可变以便在 Gateway 启动后由 `HermesGatewayService` 注入。
    /// 业务层使用 `GatewayClient.shared`，key 会自动生效。
    private(set) var apiKey: String?
    private let session: URLSession

    init(
        host: String = "127.0.0.1",
        port: Int = AppConstants.defaultGatewayPort,
        apiKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.host = host
        self.port = port
        self.apiKey = apiKey
        self.session = session
    }

    /// 注入 API key — 由 `HermesGatewayService` 在 Gateway 启动成功后调用。
    func setApiKey(_ key: String?) {
        self.apiKey = key
    }

    /// Gateway base URL，例如 `http://127.0.0.1:8642`。
    var baseUrl: String { "http://\(host):\(port)" }

    // MARK: - JSON

    /// GET 一个 JSON 端点并解析为字典。
    private func getJson(_ path: String) async -> [String: Any]? {
        guard let url = URL(string: baseUrl + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuth(&req)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard http.statusCode == 200 else {
                DMLogger.log("GET \(path) → HTTP \(http.statusCode)", name: "GatewayClient")
                return nil
            }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            DMLogger.error("GET \(path) failed: \(error)", name: "GatewayClient")
            return nil
        }
    }

    // MARK: - Sessions

    /// 拉取全部会话（`GET /api/sessions`）。
    /// 返回原始 JSON：`{"object":"list","data":[...],...}`。
    func getSessions() async -> [String: Any]? {
        await getJson("/api/sessions")
    }

    /// 删除单个会话（`DELETE /api/sessions/{id}`）。
    func deleteSession(_ id: String) async -> Bool {
        guard let url = URL(string: baseUrl + "/api/sessions/\(id)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        applyAuth(&req)
        do {
            let (_, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200 || http.statusCode == 204
        } catch {
            DMLogger.error("DELETE /api/sessions/\(id) failed: \(error)", name: "GatewayClient")
            return false
        }
    }

    /// 批量删除会话（顺序执行，任一失败即返回 false）。
    func deleteSessions(_ ids: [String]) async -> Bool {
        for id in ids {
            if !(await deleteSession(id)) { return false }
        }
        return true
    }

    /// 拉取会话完整消息历史（`GET /api/sessions/{id}/messages`）。
    func getSessionMessages(_ sessionId: String) async -> [[String: Any]]? {
        guard let json = await getJson("/api/sessions/\(sessionId)/messages") else { return nil }
        if let data = json["data"] as? [[String: Any]] {
            DMLogger.log(
                "[DEBUG] getSessionMessages: sessionId=\(sessionId) count=\(data.count) " +
                "firstMessageKeys=\(data.first?.keys.sorted() ?? [])",
                name: "GatewayClient"
            )
            return data
        }
        DMLogger.log(
            "[DEBUG] getSessionMessages: sessionId=\(sessionId) no data array, jsonKeys=\(json.keys.sorted())",
            name: "GatewayClient"
        )
        return nil
    }

    // MARK: - Chat Completions (SSE)

    /// 发起流式 Chat Completion 请求并返回 [GatewaySseStream]。
    ///
    /// - Parameters:
    ///   - request: 请求体（含 messages、model、stream、session_id）
    /// - Returns: SSE 流包装；若网络层失败则返回 status=0 的流。
    func chatCompletions(_ request: ChatCompletionRequest) async -> GatewaySseStream {
        let url = URL(string: baseUrl + "/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if request.stream {
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        applyAuth(&req)
        if let sid = request.sessionId, !sid.isEmpty {
            req.setValue(sid, forHTTPHeaderField: "X-Hermes-Session-Id")
        }
        req.httpBody = try? JSONEncoder().encode(request)

        // —— 诊断日志：完整请求体 ——
        let bodyJson = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
        DMLogger.log(
            "→ POST \(url.absoluteString) " +
            "model=\(request.model) stream=\(request.stream) " +
            "sessionId=\(request.sessionId ?? "nil") " +
            "messages=\(request.messages.count) " +
            "apiKey=\(self.apiKey != nil ? "set" : "MISSING") " +
            "bodyBytes=\(req.httpBody?.count ?? 0) " +
            "body=\(bodyJson)",
            name: "GatewayClient"
        )

        // 使用 AsyncStream 包装 URLSession bytes，按 SSE 块解析。
        var continuation: AsyncStream<GatewayStreamEvent>.Continuation!
        let stream = AsyncStream<GatewayStreamEvent> { c in
            continuation = c
        }

        // 使用 bytes(for:)（macOS 12+）逐行读取 SSE 流。
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: req)
        } catch {
            DMLogger.error(
                "chatCompletions network error: \(error.localizedDescription) " +
                "(url=\(url.absoluteString))",
                name: "GatewayClient"
            )
            return GatewaySseStream(
                events: stream,
                continuation: continuation,
                statusCode: 0,
                sessionId: nil,
                task: nil
            )
        }

        let http = response as? HTTPURLResponse
        let statusCode = http?.statusCode ?? 0
        let sessionId = http?.value(forHTTPHeaderField: "X-Hermes-Session-Id")
        let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? "?"

        // —— 诊断日志：响应首部 ——
        let allHeaders = http?.allHeaderFields.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") ?? "?"
        DMLogger.log(
            "← HTTP \(statusCode) content-type=\(contentType) " +
            "x-hermes-session-id=\(sessionId ?? "nil") " +
            "headers=[\(allHeaders)]",
            name: "GatewayClient"
        )

        // 非 200：把响应体读完并打印出来，再返回空流。
        // 这样 ChatService 才能拿到原始错误信息并向用户展示。
        if statusCode != 200 {
            var raw: [UInt8] = []
            do {
                for try await byte in bytes {
                    raw.append(byte)
                    // 防止上游错误体过大；保留前 4KB 足够诊断
                    if raw.count > 4096 { break }
                }
            } catch {
                raw.append(contentsOf:
                    "<!-- drain error: \(error.localizedDescription) -->".utf8
                )
            }
            let errorBody = String(decoding: raw, as: UTF8.self)
            DMLogger.error(
                "chatCompletions non-200: HTTP \(statusCode) body=\(errorBody)",
                name: "GatewayClient"
            )
            return GatewaySseStream(
                events: stream,
                continuation: continuation,
                statusCode: statusCode,
                sessionId: sessionId,
                task: bytes.task,
                errorBody: errorBody
            )
        }

        // 在后台 Task 中解析 SSE 流。
        Task { [weak self] in
            await self?.parseSseStream(bytes: bytes, into: continuation)
        }

        return GatewaySseStream(
            events: stream,
            continuation: continuation,
            statusCode: statusCode,
            sessionId: sessionId,
            task: bytes.task
        )
    }

    // MARK: - Non-streaming diagnostic

    /// 发起一次非流式 Chat Completion 请求并返回解析后的 JSON。
    ///
    /// 当 SSE 流返回空内容时，用于回退诊断：Hermes 的非流响应通常会带上
    /// `error` 字段（如 provider 401 Invalid token），而 SSE 流只会空跑结束。
    func chatCompletionsNonStream(_ request: ChatCompletionRequest) async -> [String: Any]? {
        let url = URL(string: baseUrl + "/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        if let sid = request.sessionId, !sid.isEmpty {
            req.setValue(sid, forHTTPHeaderField: "X-Hermes-Session-Id")
        }
        let nonStreamRequest = ChatCompletionRequest(
            messages: request.messages,
            model: request.model,
            stream: false,
            sessionId: request.sessionId,
            reasoningEffort: request.reasoningEffort
        )
        req.httpBody = try? JSONEncoder().encode(nonStreamRequest)

        DMLogger.log(
            "→ POST(non-stream) \(url.absoluteString) " +
            "model=\(nonStreamRequest.model) sessionId=\(nonStreamRequest.sessionId ?? "nil") " +
            "messages=\(nonStreamRequest.messages.count)",
            name: "GatewayClient"
        )

        do {
            let (data, response) = try await session.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            DMLogger.log(
                "← POST(non-stream) HTTP \(status) jsonKeys=\(json?.keys.sorted() ?? [])",
                name: "GatewayClient"
            )
            return json
        } catch {
            DMLogger.error("chatCompletionsNonStream error: \(error)", name: "GatewayClient")
            return nil
        }
    }

    // MARK: - SSE parsing

    /// 将 `URLSession.AsyncBytes` 解析为 SSE 事件流并 push 到 continuation。
    ///
    /// SSE 解析：兼容两种格式。
    /// 1. 标准 SSE：块以 `\n\n` 分隔，每块可能包含多行 `event:` / `data:`。
    /// 2. Hermes 简化格式：每个事件占一行 `data: {...}`，无空行分隔。
    private func parseSseStream(
        bytes: URLSession.AsyncBytes,
        into continuation: AsyncStream<GatewayStreamEvent>.Continuation
    ) async {
        var buffer = ""
        let lineSeparator: Character = "\n"

        do {
            var lineNumber = 0
            for try await lineRaw in bytes.lines {
                lineNumber += 1
                // bytes.lines 已按 `\n` 切分（去掉了 `\n`）
                let visible = lineRaw.count > 500 ? String(lineRaw.prefix(500)) + "…" : lineRaw
                DMLogger.log("SSE raw line #\(lineNumber): \(visible)", name: "GatewayClient")

                // Hermes 简化格式：一行就是一个 data 事件，直接解析。
                if lineRaw.hasPrefix("data: ") || lineRaw.hasPrefix("data:") {
                    if let evts = parseSseBlock(String(lineRaw)) {
                        DMLogger.log("SSE single-line yielded events=\(evts.count)", name: "GatewayClient")
                        for evt in evts {
                            continuation.yield(evt)
                        }
                    } else {
                        DMLogger.log("SSE single-line yielded no events", name: "GatewayClient")
                    }
                    continue
                }

                // 标准 SSE：按 \n\n 分块。
                buffer.append(lineRaw)
                buffer.append(lineSeparator)

                while let range = buffer.range(of: "\n\n") {
                    let block = String(buffer[..<range.lowerBound])
                    buffer.removeSubrange(buffer.startIndex...range.upperBound)
                    DMLogger.log("SSE block parsed, linesInBlock=\(block.split(separator: "\n").count)", name: "GatewayClient")

                    if let evts = parseSseBlock(block) {
                        DMLogger.log("SSE block yielded events=\(evts.count)", name: "GatewayClient")
                        for evt in evts {
                            continuation.yield(evt)
                        }
                    } else {
                        DMLogger.log("SSE block yielded no events", name: "GatewayClient")
                    }
                }
            }
            // 处理尾块
            if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let evts = parseSseBlock(buffer) {
                    for evt in evts {
                        continuation.yield(evt)
                    }
                }
            }
        } catch {
            DMLogger.error("SSE parse error: \(error)", name: "GatewayClient")
        }
        continuation.finish()
    }

    /// 解析单个 SSE 块，可能产生多个事件。
    ///
    /// 标准 SSE 应当形如：
    /// ```
    /// data: {"choices":[...]}
    /// <blank>
    /// ```
    /// 但 Hermes 在某些情况下会把多个 JSON chunk 拼到同一行（用 `}{` 衔接，
    /// 没有换行、没有重复的 `data:` 前缀），形如：
    /// ```
    /// data: {"choices":[…,"finish_reason":null}]}{"choices":[…,"finish_reason":"stop"],"usage":{…}}[DONE]
    /// ```
    /// 这里需要把这种拼接识别出来，逐个 yield。
    ///
    /// `[DONE]`（无论独立成行还是拼在末尾）始终终止当前块。
    /// - Returns: 0 个或多个 [GatewayStreamEvent]；返回 `nil` 表示无数据。
    private func parseSseBlock(_ block: String) -> [GatewayStreamEvent]? {
        var event: String?
        var data: String?

        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("event: ") {
                event = String(line.dropFirst("event: ".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data: ") {
                // 去掉行尾可能残留的 \r，避免 CRLF 导致 JSON 解析失败。
                data = (data ?? "") + String(line.dropFirst("data: ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.hasPrefix("data:") {
                data = (data ?? "") + String(line.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let raw = data, !raw.isEmpty else { return nil }
        if raw == "[DONE]" { return nil }

        // 处理 Hermes 把多个 JSON chunk 拼到同一行的情况：
        //   {...}{...}{...}[DONE]
        // 先把末尾可能追加的 [DONE] 剥掉（如果整串就是 [DONE]，上面已经 return）
        let jsonText: String
        if raw.hasSuffix("[DONE]") {
            jsonText = String(raw.dropLast("[DONE]".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            jsonText = raw
        }
        guard !jsonText.isEmpty else { return nil }

        let chunks = splitConcatenatedJsonObjects(jsonText)
        guard !chunks.isEmpty else {
            DMLogger.log("parseSseBlock: no JSON chunks from raw", name: "GatewayClient")
            return nil
        }
        DMLogger.log(
            "parseSseBlock: yielded \(chunks.count) chunk(s), firstBytes=\(chunks.first?.count ?? 0)",
            name: "GatewayClient"
        )
        return chunks.map { GatewayStreamEvent(event: event, data: $0, id: nil) }
    }

    /// 把可能由多个 JSON 对象拼接（用 `}{` 衔接）的字符串拆成多个。
    /// 只在顶层 JSON 对象的边界切分，不在字符串内/嵌套对象的边界切分。
    private func splitConcatenatedJsonObjects(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        var depth = 0
        var inString = false
        var escape = false

        for c in text {
            current.append(c)
            if escape {
                escape = false
                continue
            }
            if c == "\\" {
                escape = true
                continue
            }
            if c == "\"" {
                inString.toggle()
                continue
            }
            if inString { continue }
            if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 {
                    chunks.append(current)
                    current = ""
                }
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    // MARK: - Helpers

    private func applyAuth(_ req: inout URLRequest) {
        if let apiKey = apiKey, !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }
}
