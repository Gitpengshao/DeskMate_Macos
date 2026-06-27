import Foundation

/// 工具进度状态。
enum ToolProgressStatus: String, Equatable {
    case running
    case completed
    case failed
}

/// Hermes `hermes.tool.progress` 事件内容。
struct ToolProgressEvent: Identifiable, Equatable {
    let id: String
    let tool: String
    let emoji: String
    let label: String
    let status: ToolProgressStatus
    let toolCallId: String?

    init(
        tool: String,
        emoji: String,
        label: String,
        status: ToolProgressStatus,
        toolCallId: String? = nil
    ) {
        self.tool = tool
        self.emoji = emoji
        self.label = label
        self.status = status
        self.toolCallId = toolCallId
        self.id = toolCallId ?? "\(tool)-\(label)-\(Date().timeIntervalSince1970)"
    }
}

/// Chat 流事件 — 对齐 Flutter `ChatStreamEvent`（sealed class 层级）。
enum ChatStreamEvent {
    /// 后端分配的新会话 ID。
    case sessionCreated(String)
    /// 文本增量块。
    case deltaChunk(String)
    /// AI 调用工具。
    case toolCall(name: String, arguments: [String: Any], displayText: String)
    /// 工具执行进度（Hermes 自定义事件）。
    case toolProgress(ToolProgressEvent)
    /// 流正常结束。
    case streamCompleted
    /// 流错误。
    case streamError(String)
}

/// 后端 DB 同步回来的消息 — 对齐 Flutter `SyncedMessage`。
struct SyncedMessage {
    let id: String
    let role: String       // "user" / "assistant" / "system" / "tool"
    let content: String
    let toolCallId: String?

    init(from json: [String: Any]) {
        self.id = (json["id"] as? String) ?? ""
        self.role = (json["role"] as? String) ?? "user"
        self.content = (json["content"] as? String) ?? ""
        self.toolCallId = json["tool_call_id"] as? String
    }
}

/// 封装 Hermes Gateway SSE Chat API — 对齐 Flutter `ChatService`。
///
/// 通过 [GatewayClient] 发起 `POST /v1/chat/completions`，
/// 解析 OpenAI-compatible 增量块与 Hermes 自定义 `hermes.tool.progress` 事件。
final class ChatService {

    private let gateway: GatewayClient
    private var currentStream: GatewaySseStream?
    private var streamTask: Task<Void, Never>?
    /// 当前 SSE 流是否收到过有效内容增量或工具调用增量。
    private var receivedContent: Bool = false

    init(gatewayClient: GatewayClient) {
        self.gateway = gatewayClient
    }

    var isStreaming: Bool { currentStream != nil }

    /// 发起一次 Chat Completion 流式请求。
    ///
    /// - Parameters:
    ///   - messages: 全部历史消息（含本次用户消息）。
    ///   - sessionId: 已有会话 ID（可选；为空时后端会创建新会话）。
    ///   - reasoningEffort: 本次请求级别的推理强度覆盖（与 `~/.hermes/config.yaml`
    ///     中 `agent.reasoning_effort` 等价；详见官方文档）。
    ///   - onEvent: 收到事件时回调（在主线程触发，方便 UI 更新）。
    ///   - onComplete: 流结束后回调（无论成功或错误都会触发一次）。
    func chat(
        messages: [GatewayChatMessage],
        sessionId: String?,
        reasoningEffort: String? = nil,
        onEvent: @escaping (ChatStreamEvent) -> Void,
        onComplete: @escaping () -> Void
    ) {
        let request = ChatCompletionRequest(
            messages: messages,
            model: "hermes-agent",
            stream: true,
            sessionId: sessionId,
            reasoningEffort: reasoningEffort
        )

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self = self else { return }

            // 每次新流重置内容标记
            self.receivedContent = false

            // —— 诊断日志：发起请求前 ——
            DMLogger.log(
                "chat() start: model=hermes-agent stream=true " +
                "sessionId=\(sessionId ?? "nil") " +
                "reasoning_effort=\(reasoningEffort ?? "nil") " +
                "messages=\(messages.count) " +
                "lastRole=\(messages.last?.role ?? "?") " +
                "lastContentLen=\(messages.last?.content.count ?? 0)",
                name: "ChatService"
            )

            let sse = await self.gateway.chatCompletions(request)
            self.currentStream = sse

            DMLogger.log(
                "chat() sse received: status=\(sse.statusCode) " +
                "sessionId=\(sse.sessionId ?? "nil") " +
                "errorBody=\(sse.errorBody ?? "nil")",
                name: "ChatService"
            )

            if sse.statusCode != 200 {
                // 优先把上游错误体回显给用户；否则退到通用提示
                let body = (sse.errorBody ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let reason: String
                if !body.isEmpty {
                    // 截断避免 UI 气泡过长
                    let trimmed = body.count > 500
                        ? String(body.prefix(500)) + "…"
                        : body
                    reason = "HTTP \(sse.statusCode): \(trimmed)"
                } else {
                    reason = "连接失败 (HTTP \(sse.statusCode))"
                }
                DMLogger.error("chat() failing through with reason: \(reason)", name: "ChatService")
                onEvent(.streamError(reason))
                onComplete()
                self.cleanup()
                return
            }

            // 后端分配的新 sessionId
            if let sid = sse.sessionId, !sid.isEmpty {
                onEvent(.sessionCreated(sid))
            }

            // 遍历 SSE 事件
            var eventCount = 0
            do {
                for try await event in sse.events {
                    if Task.isCancelled { break }
                    eventCount += 1

                    // —— 诊断：完整打印前 3 条 + 每 20 条 —
                    // 200 字符截断会丢掉 finish_reason / usage 等关键字段
                    if eventCount <= 3 || eventCount % 20 == 0 {
                        let raw = event.data ?? ""
                        DMLogger.log(
                            "chat() SSE event #\(eventCount) " +
                            "type=\(event.event ?? "delta") " +
                            "dataBytes=\(raw.count) " +
                            "data=\(raw)",
                            name: "ChatService"
                        )

                        // 单独抽出诊断关键字段
                        if let json = event.dataAsJson,
                           let choices = json["choices"] as? [[String: Any]],
                           let first = choices.first {
                            let delta = first["delta"] as? [String: Any] ?? [:]
                            let finish = first["finish_reason"] as? String ?? "nil"
                            let role = delta["role"] as? String ?? "?"
                            let contentLen = (delta["content"] as? String)?.count ?? 0
                            DMLogger.log(
                                "chat() SSE #\(eventCount) parsed: " +
                                "role=\(role) deltaContentLen=\(contentLen) " +
                                "finish_reason=\(finish)",
                                name: "ChatService"
                            )
                        }
                        if let json = event.dataAsJson,
                           let usage = json["usage"] as? [String: Any] {
                            DMLogger.log(
                                "chat() SSE #\(eventCount) usage=\(usage)",
                                name: "ChatService"
                            )
                        }
                    }
                    self.processEvent(event, onEvent: onEvent)
                }
                DMLogger.log(
                    "chat() SSE loop done: eventCount=\(eventCount) " +
                    "receivedContent=\(self.receivedContent) " +
                    "streamAlive=\(self.currentStream != nil ? "yes" : "no")",
                    name: "ChatService"
                )

                if Task.isCancelled {
                    DMLogger.log("chat() SSE loop cancelled", name: "ChatService")
                    onEvent(.streamCompleted)
                } else if eventCount > 0 && !self.receivedContent {
                    // SSE 空跑结束：发起一次非流式探测，读取 gateway 返回的真实错误。
                    DMLogger.log(
                        "chat() empty SSE stream: running non-stream diagnostic",
                        name: "ChatService"
                    )
                    let handled = await self.diagnoseEmptyStream(request: request, onEvent: onEvent)
                    if !handled {
                        onEvent(.streamCompleted)
                    }
                } else {
                    DMLogger.log(
                        "chat() SSE loop finished normally, eventCount=\(eventCount), " +
                        "receivedContent=\(self.receivedContent)",
                        name: "ChatService"
                    )
                    onEvent(.streamCompleted)
                }
            } catch {
                DMLogger.error(
                    "chat() SSE loop error: \(error.localizedDescription) " +
                    "after eventCount=\(eventCount)",
                    name: "ChatService"
                )
                onEvent(.streamError(error.localizedDescription))
            }

            DMLogger.log(
                "chat() calling onComplete, eventCount=\(eventCount), " +
                "receivedContent=\(self.receivedContent)",
                name: "ChatService"
            )
            onComplete()
            self.cleanup()
        }
    }

    /// 当 SSE 流没有收到任何内容增量时，用非流式请求拉回真实错误信息。
    ///
    /// Hermes 的 SSE 实现在 provider 失败时只返回空的 assistant/finish 块，
    /// 非流式响应才会暴露 `error.message`（如 401 Invalid token）。
    /// - Returns: `true` 表示诊断已经通过 `onEvent` 分发了结果（错误/内容），
    ///   调用方不要再补发 `streamCompleted`。
    private func diagnoseEmptyStream(
        request: ChatCompletionRequest,
        onEvent: (ChatStreamEvent) -> Void
    ) async -> Bool {
        let json = await gateway.chatCompletionsNonStream(request)
        DMLogger.log(
            "diagnoseEmptyStream: jsonKeys=\(json?.keys.sorted() ?? [])",
            name: "ChatService"
        )
        if let error = json?["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "未知上游错误"
            let code = (error["code"] as? String) ?? "?"
            DMLogger.error(
                "diagnoseEmptyStream: upstream error [\(code)]: \(message)",
                name: "ChatService"
            )
            onEvent(.streamError("模型调用失败 [\(code)]: \(message)"))
            return true
        }
        if let choices = json?["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String, !content.isEmpty {
            // 非流式返回了内容：说明流式后端行为异常，把内容作为增量展示给用户。
            DMLogger.log(
                "diagnoseEmptyStream: non-stream returned \(content.count) chars",
                name: "ChatService"
            )
            self.receivedContent = true
            onEvent(.deltaChunk(content))
            onEvent(.streamCompleted)
            return true
        }
        return false
    }

    /// 取消当前流（与 Flutter `cancelStream` 等价）。
    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        currentStream?.cancel()
        currentStream = nil
    }

    /// 从后端 DB 同步当前会话的完整消息列表。
    ///
    /// 与 Flutter `syncSessionMessages` 行为一致：流结束后用于校准本地状态。
    func syncSessionMessages(_ sessionId: String) async -> [SyncedMessage] {
        guard let raw = await gateway.getSessionMessages(sessionId), !raw.isEmpty else {
            return []
        }
        return raw.map { SyncedMessage(from: $0) }
    }

    // MARK: - Private

    /// 处理单个 SSE 事件，分发为类型化的 [ChatStreamEvent]。
    ///
    /// - 当 event 为 nil：标准 OpenAI 增量格式 `{"choices":[{"delta":{"content":"..."}}]}`。
    /// - 当 event == "hermes.tool.progress"：Hermes 自定义工具进度。
    private func processEvent(
        _ event: GatewayStreamEvent,
        onEvent: (ChatStreamEvent) -> Void
    ) {
        guard let json = event.dataAsJson else {
            DMLogger.log(
                "processEvent: data is not JSON, event=\(event.event ?? "nil") data=\(event.data ?? "nil")",
                name: "ChatService"
            )
            return
        }
        let eventType = event.event

        DMLogger.log(
            "processEvent: eventType=\(eventType ?? "delta") topKeys=\(json.keys.sorted())",
            name: "ChatService"
        )

        // 某些网关错误会直接在 SSE 块里带 `error` 字段
        if let error = json["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "未知上游错误"
            let code = (error["code"] as? String) ?? "?"
            DMLogger.error("processEvent: upstream error in SSE: [\(code)] \(message)", name: "ChatService")
            onEvent(.streamError("模型调用失败 [\(code)]: \(message)"))
            return
        }

        if eventType == nil {
            // Hermes 可能把工具进度也作为无 event 行的 data 发送。
            if let tool = json["tool"] as? String, !tool.isEmpty {
                let emoji = (json["emoji"] as? String) ?? ""
                let label = (json["label"] as? String) ?? tool
                let toolCallId = json["toolCallId"] as? String
                let statusString = (json["status"] as? String) ?? "running"
                let status: ToolProgressStatus
                switch statusString {
                case "completed": status = .completed
                case "failed", "error": status = .failed
                default: status = .running
                }
                self.receivedContent = true
                let progress = ToolProgressEvent(
                    tool: tool,
                    emoji: emoji,
                    label: label,
                    status: status,
                    toolCallId: toolCallId
                )
                DMLogger.log(
                    "processEvent: emitting toolProgress tool=\(tool) status=\(statusString)",
                    name: "ChatService"
                )
                onEvent(.toolProgress(progress))
                return
            }

            // OpenAI 兼容格式
            guard let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first else {
                DMLogger.log("processEvent: no choices", name: "ChatService")
                return
            }
            guard let delta = choice["delta"] as? [String: Any] else {
                DMLogger.log("processEvent: choice has no delta", name: "ChatService")
                return
            }

            DMLogger.log(
                "processEvent: delta keys=\(delta.keys.sorted()) values=\(delta)",
                name: "ChatService"
            )

            // 文本增量
            let contentCandidate = delta["content"] as? String
            let contentLen = contentCandidate?.count ?? 0
            if let content = contentCandidate, !content.isEmpty {
                self.receivedContent = true
                DMLogger.log(
                    "processEvent: emitting deltaChunk len=\(contentLen) content=\(content)",
                    name: "ChatService"
                )
                onEvent(.deltaChunk(content))
            } else {
                DMLogger.log(
                    "processEvent: content empty or missing (len=\(contentLen))",
                    name: "ChatService"
                )
            }

            // 工具调用增量
            if let toolCalls = delta["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                self.receivedContent = true
                for tc in toolCalls {
                    if let fn = tc["function"] as? [String: Any] {
                        let name = (fn["name"] as? String) ?? "unknown"
                        let argsStr = (fn["arguments"] as? String) ?? "{}"
                        var arguments: [String: Any] = ["raw": argsStr]
                        if let data = argsStr.data(using: .utf8),
                           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            arguments = parsed
                        }
                        let displayText = "🔧 已调用: \(name)(\(argsStr))"
                        onEvent(.toolCall(name: name, arguments: arguments, displayText: displayText))
                    }
                }
            }
        } else if eventType == "hermes.tool.progress" {
            // Hermes 自定义工具进度事件：提取结构化字段供 UI 渲染为进度条/芯片。
            let tool = (json["tool"] as? String) ?? ""
            let emoji = (json["emoji"] as? String) ?? ""
            let label = (json["label"] as? String) ?? tool
            let toolCallId = json["toolCallId"] as? String
            let statusString = (json["status"] as? String) ?? "running"
            let status: ToolProgressStatus
            switch statusString {
            case "completed": status = .completed
            case "failed", "error": status = .failed
            default: status = .running
            }
            if !tool.isEmpty || !label.isEmpty {
                self.receivedContent = true
                let progress = ToolProgressEvent(
                    tool: tool,
                    emoji: emoji,
                    label: label,
                    status: status,
                    toolCallId: toolCallId
                )
                onEvent(.toolProgress(progress))
            }
        } else {
            DMLogger.log("Unhandled event type: \(eventType ?? "?")", name: "ChatService")
        }
    }

    private func cleanup() {
        currentStream = nil
        streamTask = nil
    }
}
