import Foundation
import SwiftUI
import Combine

/// AI 对话页面 ViewModel — 对齐 Flutter `AiChatViewModel`（Riverpod Notifier）。
///
/// MVVM：管理 `model: AiChatModel` 单一状态源，
/// 通过 `@Published` 通知 SwiftUI 视图刷新。
@MainActor
final class AiChatViewModel: ObservableObject {

    @Published var model: AiChatModel

    /// 与 Flutter `hermesServiceProvider` 等价的依赖注入入口；
    /// 默认指向 `127.0.0.1:8642`。
    private let gateway: GatewayClient
    private let chatService: ChatService
    /// 读取 `~/.hermes/config.yaml` 中默认模型 — 驱动 header 徽标显示。
    private let modelConfigService: ModelConfigService

    /// 读取 / 写入配置 — 始终与当前 Gateway 运行的 profile 对齐。
    ///
    /// 官方文档明确区分 profile 与 workspace：
    /// `terminal.cwd` 必须写入 Gateway 实际使用的 profile 的 `config.yaml`，
    /// 否则工作区不会生效（文件会创建到默认 `~/.hermes` 或其他目录）。
    private var configWriter: HermesConfigWriter {
        HermesConfigWriter.forProfile(HermesGatewayService.shared.currentProfile)
    }

    /// SSE 流缓冲（与 Flutter `_streamBuffer` 等价）。
    private var streamBuffer: String = ""

    /// 灵动岛工作态是否已触发 — 首个 deltaChunk 时设为 true，结束后复位
    private var hasStartedWorking: Bool = false

    init(
        gateway: GatewayClient? = nil,
        modelConfigService: ModelConfigService? = nil,
        configWriter: HermesConfigWriter? = nil,
        petEmoji: String = "🐱",
        petNameKey: String = "petNameHuahua"
    ) {
        // 在 @MainActor 隔离的 init 体内构造默认值，
        // 避免在默认参数（nonisolated 上下文）中调用 main actor-isolated 初始化器。
        // 使用 GatewayClient.shared 以便 HermesGatewayService 启动后注入的 apiKey 生效。
        let resolvedGateway = gateway ?? GatewayClient.shared
        self.gateway = resolvedGateway
        self.chatService = ChatService(gatewayClient: resolvedGateway)
        self.modelConfigService = modelConfigService ?? ModelConfigService()
        // 初始读取使用当前 profile（通常是 nil，即默认 `~/.hermes`）；
        // 页面 onAppear 会再次刷新，确保 Gateway 启动后拿到最新值。
        let initialWriter = configWriter ?? HermesConfigWriter.forProfile(HermesGatewayService.shared.currentProfile)
        // 从 config.yaml 同步当前推理强度（保持与官方默认值兼容）。
        let loaded = initialWriter.readReasoningEffort()
        // 从 config.yaml 同步当前工作区目录。
        let cwd = initialWriter.readTerminalCwd()
        self.model = AiChatModel(
            petEmoji: petEmoji,
            petNameKey: petNameKey,
            reasoningEffort: loaded,
            workingDirectory: cwd
        )
    }

    // MARK: - Input

    /// 更新输入框文本 — 对齐 Flutter `updateInput`。
    func updateInput(_ text: String) {
        model.inputText = text
    }

    /// 添加选中的文件/目录引用到输入框。
    func addReference(path: String, isDirectory: Bool) {
        let item = ReferenceItem(
            id: path,
            path: path,
            isDirectory: isDirectory
        )
        // 避免重复添加
        guard !model.selectedReferences.contains(where: { $0.id == item.id }) else { return }
        model.selectedReferences.append(item)
    }

    /// 移除指定引用。
    func removeReference(_ id: String) {
        model.selectedReferences.removeAll { $0.id == id }
    }

    /// 清空全部引用。
    func clearReferences() {
        model.selectedReferences = []
    }

    // MARK: - Send

    /// 发送当前输入文本并启动 SSE 流 — 对齐 Flutter `sendMessage`。
    func sendMessage() {
        let text = model.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // 将引用路径拼接到实际发送的文本中
        let refText = model.referenceText
        let fullText: String
        if refText.isEmpty {
            fullText = text
        } else if text.isEmpty {
            fullText = refText
        } else {
            fullText = text + " " + refText
        }
        guard !fullText.isEmpty, !model.isStreaming else { return }

        // 1. 构造用户消息并加入列表
        let userMsg = ChatMessage(
            id: String(Int(Date().timeIntervalSince1970 * 1000)),
            sender: .user,
            text: fullText,
            timestamp: nowTime()
        )

        DMLogger.log(
            "[DEBUG] sendMessage: adding userMsg id=\(userMsg.id), " +
            "current messages count=\(model.messages.count)",
            name: "AiChatVM"
        )

        model.messages.append(userMsg)
        model.inputText = ""
        model.selectedReferences = []
        model.isLoading = true
        model.connectionState = .connecting
        model.errorMessage = nil
        model.streamingContent = nil
        model.toolProgressEvents = []

        // 防御性复位工作态 — 避免上一次未正确清理导致重复触发
        hasStartedWorking = false

        DMLogger.log(
            "[DEBUG] sendMessage: state updated, " +
            "messages count=\(model.messages.count), " +
            "sessionId=\(model.sessionId ?? "nil")",
            name: "AiChatVM"
        )

        // 2. 构造 gateway 消息（全部历史）
        let gwMessages = buildGatewayMessages(model.messages)

        // 3. 重置缓冲并启动流
        streamBuffer = ""

        DMLogger.log(
            "[DEBUG] sendMessage: invoking chatService.chat, " +
            "gwMessages=\(gwMessages.count), sessionId=\(model.sessionId ?? "nil")",
            name: "AiChatVM"
        )

        chatService.chat(
            messages: gwMessages,
            sessionId: model.sessionId,
            reasoningEffort: model.reasoningEffort.rawValue
        ) { [weak self] event in
            Task { @MainActor in
                self?.onStreamEvent(event)
            }
        } onComplete: { [weak self] in
            Task { @MainActor in
                self?.onStreamDone()
            }
        }

        DMLogger.log(
            "[DEBUG] sendMessage: SSE stream started with reasoning_effort=" +
            "\(model.reasoningEffort.rawValue)",
            name: "AiChatVM"
        )
    }

    // MARK: - Stream events

    /// 处理单个流事件 — 对齐 Flutter `_onStreamEvent`。
    private func onStreamEvent(_ event: ChatStreamEvent) {
        switch event {
        case .sessionCreated(let sessionId):
            DMLogger.log("[DEBUG] SessionCreated: \(sessionId)", name: "AiChatVM")
            model.sessionId = sessionId

        case .deltaChunk(let text):
            // 首个 deltaChunk 触发灵动岛工作态（与 think 动画结束同步）
            if !hasStartedWorking {
                hasStartedWorking = true
                DynamicNotchManager.shared.startWorking()
            }
            streamBuffer.append(text)
            DMLogger.log(
                "[DEBUG] DeltaChunk: text=\"\(text)\", buffer length=\(streamBuffer.count)",
                name: "AiChatVM"
            )
            model.streamingContent = streamBuffer
            model.connectionState = .streaming

        case .toolCall(_, _, let displayText):
            DMLogger.log("[DEBUG] ToolCall: \(displayText)", name: "AiChatVM")
            // 与 Flutter 一致：不插入独立的 tool 消息气泡，
            // 仅保留 streamingContent 便于流继续拼接。
            model.streamingContent = streamBuffer

        case .toolProgress(let event):
            DMLogger.log(
                "[DEBUG] ToolProgress: tool=\(event.tool) status=\(event.status.rawValue) label=\(event.label)",
                name: "AiChatVM"
            )
            // 同一 toolCallId 的进度更新替换旧记录，避免列表无限增长。
            // 通过赋值新数组触发 @Published，确保同一 event 从 running -> completed 也能刷新 UI。
            var events = model.toolProgressEvents
            if let idx = events.firstIndex(where: {
                $0.toolCallId == event.toolCallId && $0.toolCallId != nil
            }) {
                events[idx] = event
            } else {
                events.append(event)
            }
            model.toolProgressEvents = events
            model.connectionState = .streaming

        case .streamCompleted:
            DMLogger.log(
                "[DEBUG] StreamCompleted event, buffer length=\(streamBuffer.count), " +
                "connectionState=\(model.connectionState.rawValue)",
                name: "AiChatVM"
            )
            // 由 onStreamDone 处理
            break

        case .streamError(let message):
            handleError(message)
        }
    }

    /// 流结束处理 — 对齐 Flutter `_onStreamDone`。
    private func onStreamDone() {
        let fullContent = streamBuffer
        let preview = fullContent.count > 200
            ? String(fullContent.prefix(200)) + "…"
            : fullContent

        DMLogger.log(
            "[DEBUG] _onStreamDone: fullContent length=\(fullContent.count), " +
            "connectionState=\(model.connectionState.rawValue), " +
            "messages count=\(model.messages.count), " +
            "preview=\(preview)",
            name: "AiChatVM"
        )

        if fullContent.isEmpty && model.connectionState == .connecting {
            DMLogger.log(
                "[DEBUG] _onStreamDone: empty content, handling as error",
                name: "AiChatVM"
            )
            handleError("未收到回复")
            return
        }

        if fullContent.isEmpty {
            DMLogger.log(
                "[DEBUG] _onStreamDone: WARNING fullContent empty but state=\(model.connectionState.rawValue), " +
                "will insert placeholder",
                name: "AiChatVM"
            )
        }

        // 加入助手消息
        let assistantMsg = ChatMessage(
            id: "\(Int(Date().timeIntervalSince1970 * 1000))_pet",
            sender: .pet,
            text: fullContent.isEmpty ? "..." : fullContent,
            timestamp: nowTime()
        )

        DMLogger.log(
            "[DEBUG] _onStreamDone: adding assistantMsg id=\(assistantMsg.id), " +
            "text length=\(assistantMsg.text.count)",
            name: "AiChatVM"
        )

        model.messages.append(assistantMsg)

        model.streamingContent = nil
        model.toolProgressEvents = []
        model.isLoading = false
        model.connectionState = .completed

        // 流结束 → 收回灵动岛工作态
        if hasStartedWorking {
            hasStartedWorking = false
            DynamicNotchManager.shared.stopWorking()
        }

        DMLogger.log(
            "[DEBUG] _onStreamDone: state updated, " +
            "messages count=\(model.messages.count)",
            name: "AiChatVM"
        )

        // 后端 DB 同步：仅用于校准 connectionState，不替换本地消息
        syncFromDatabase()
    }

    /// 后端 DB 同步 — 对齐 Flutter `_syncFromDatabase`。
    ///
    /// 流结束后从 Hermes 数据库拉取当前会话的完整消息列表，
    /// 仅用于校准 connectionState，不替换本地消息，
    /// 避免与 SSE 已渲染的内容重复。
    private func syncFromDatabase() {
        guard let sessionId = model.sessionId else {
            DMLogger.log(
                "[DEBUG] _syncFromDatabase: no sessionId, setting idle directly",
                name: "AiChatVM"
            )
            model.connectionState = .idle
            return
        }
        Task { [weak self] in
            guard let self = self else { return }
            DMLogger.log(
                "[DEBUG] _syncFromDatabase: fetching session messages for \(sessionId)",
                name: "AiChatVM"
            )
            let synced = await self.chatService.syncSessionMessages(sessionId)

            DMLogger.log(
                "[DEBUG] _syncFromDatabase: received \(synced.count) messages from DB, " +
                "local messages count=\(self.model.messages.count)",
                name: "AiChatVM"
            )

            if synced.isEmpty {
                await MainActor.run {
                    self.model.connectionState = .idle
                }
                return
            }

            // 与 Flutter 一致：逐条打印同步消息用于调试
            for (i, m) in synced.enumerated() {
                DMLogger.log(
                    "[DEBUG] _syncFromDatabase: DB[\(i)] role=\(m.role), " +
                    "content length=\(m.content.count), id=\(m.id)",
                    name: "AiChatVM"
                )
            }

            await MainActor.run {
                // 仅更新连接状态，不替换本地消息
                self.model.connectionState = .idle
            }
            DMLogger.log(
                "[DEBUG] _syncFromDatabase: done, connectionState -> idle",
                name: "AiChatVM"
            )
        }
    }

    /// 重试 — 对齐 Flutter `retry`。
    func retry() {
        guard !model.messages.isEmpty else { return }

        model.connectionState = .idle
        model.errorMessage = nil

        // 找到最后一条用户消息并重发
        if let lastUser = model.messages.last(where: { $0.sender == .user }) {
            model.inputText = lastUser.text
            sendMessage()
        }
    }

    /// 停止当前 SSE 流 — 用户点击停止按钮时调用。
    ///
    /// 取消底层 HTTP/SSE 连接以中断 Hermes agent loop 的继续输出，
    /// 并把已生成的部分内容保留为一条助手消息。
    func stopStream() {
        guard model.isStreaming else { return }

        DMLogger.log(
            "[DEBUG] stopStream: cancelling stream, " +
            "buffer length=\(streamBuffer.count), " +
            "messages count=\(model.messages.count)",
            name: "AiChatVM"
        )

        chatService.cancelStream()

        let partialContent = streamBuffer
        if !partialContent.isEmpty {
            let assistantMsg = ChatMessage(
                id: "\(Int(Date().timeIntervalSince1970 * 1000))_pet",
                sender: .pet,
                text: partialContent,
                timestamp: nowTime()
            )
            model.messages.append(assistantMsg)
            DMLogger.log(
                "[DEBUG] stopStream: preserved partial message, " +
                "text length=\(assistantMsg.text.count)",
                name: "AiChatVM"
            )
        }

        model.streamingContent = nil
        model.toolProgressEvents = []
        model.isLoading = false
        model.connectionState = .idle
        streamBuffer = ""

        // 手动停止 → 收回灵动岛工作态
        if hasStartedWorking {
            hasStartedWorking = false
            DynamicNotchManager.shared.stopWorking()
        }

        DMLogger.log(
            "[DEBUG] stopStream: state reset, connectionState -> idle",
            name: "AiChatVM"
        )
    }

    // MARK: - Session management

    /// 加载历史会话消息 — 对齐 Flutter `loadSession`。
    ///
    /// 从 Hermes Gateway 数据库查询指定会话的全部消息历史。
    func loadSession(_ sessionId: String) {
        guard !model.isStreaming else { return }

        DMLogger.log(
            "[DEBUG] loadSession: loading sessionId=\(sessionId)",
            name: "AiChatVM"
        )

        model.isLoading = true
        model.errorMessage = nil
        model.streamingContent = nil

        Task { [weak self] in
            guard let self = self else { return }
            let raw = await self.gateway.getSessionMessages(sessionId)

            // 与 Flutter 一致：null 或空列表时仅设置 sessionId，清空消息
            if raw == nil || raw?.isEmpty == true {
                await MainActor.run {
                    self.model.sessionId = sessionId
                    self.model.messages = []
                    self.model.isLoading = false
                    self.model.connectionState = .idle
                }
                return
            }

            let messages: [ChatMessage] = raw!.map { m in
                let role = self.castToString(m["role"]) ?? "user"
                let sender: MessageSender
                switch role {
                case "user": sender = .user
                case "tool": sender = .tool
                default:     sender = .pet
                }
                let id = self.castToString(m["id"])
                    ?? String(Int(Date().timeIntervalSince1970 * 1000))
                let content = self.castToString(m["content"]) ?? ""
                return ChatMessage(
                    id: id,
                    sender: sender,
                    text: content,
                    timestamp: self.nowTime()
                )
            }

            DMLogger.log(
                "[DEBUG] loadSession: loaded \(messages.count) messages for \(sessionId)",
                name: "AiChatVM"
            )

            await MainActor.run {
                self.model.sessionId = sessionId
                self.model.messages = messages
                self.model.isLoading = false
                self.model.connectionState = .idle
            }
        }
    }

    /// 开始新会话 — 对齐 Flutter `newSession`。
    func newSession() {
        guard !model.isStreaming else { return }
        DMLogger.log("[DEBUG] newSession: clearing chat", name: "AiChatVM")
        model.messages = []
        model.sessionId = nil
        model.sessionTitle = nil
        model.inputText = ""
        model.selectedReferences = []
        model.streamingContent = nil
        model.errorMessage = nil
        model.connectionState = .idle
        streamBuffer = ""
    }

    /// 切换侧边栏可见性 — 对齐 Flutter `toggleSidebar`。
    func toggleSidebar() {
        model.sidebarVisible.toggle()
    }

    // MARK: - Model config

    /// 从 `~/.hermes/config.yaml` 读取当前默认模型并写入 `model.currentModel`。
    ///
    /// 文档依据（Configuring Models）：
    /// > 写入 `model.default` 后，新会话会使用该模型；正在运行的会话保留启动时的模型。
    /// > UI 展示的"当前默认模型"即 `config.yaml` 中 `model.default` 的值。
    ///
    /// - 失败/缺失/未配置时不抛错，仅保持 `currentModel == nil`，
    ///   调用方（header）会显示 "未配置" 占位。
    func loadCurrentModel() {
        Task { [weak self] in
            guard let self = self else { return }
            let info = await Task.detached(priority: .userInitiated) {
                self.modelConfigService.readCurrentModel()
            }.value

            await MainActor.run {
                self.model.currentModel = info
                DMLogger.log(
                    "loadCurrentModel: currentModel=\(info?.fullName ?? "nil")",
                    name: "AiChatVM"
                )
            }
        }
    }

    // MARK: - Reasoning effort

    /// 切换推理强度 — 同步更新 `model.reasoningEffort` 并写入 `~/.hermes/config.yaml`。
    ///
    /// 官方文档：
    /// [`agent.reasoning_effort`](https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/configuration#%E6%8E%A8%E7%90%86%E5%8A%AA%E5%8A%9B%E7%A8%8B%E5%BA%A6)
    /// 可选值：`none | low | minimal | medium | high | xhigh`。
    ///
    /// - 行为等价于 `hermes config set agent.reasoning_effort <value>`，但**仅修改
    ///   `reasoning_effort` 字段**，不触动 `agent:` 块中的其它配置。
    /// - 持久化失败仅记日志，不抛错；UI 仍按用户最新选择生效（请求级覆盖）。
    /// - 不影响进行中的流 — 切换仅对**下一次** `sendMessage()` 生效。
    func setReasoningEffort(_ effort: ReasoningEffort) {
        DMLogger.log(
            "setReasoningEffort: \(model.reasoningEffort.rawValue) -> \(effort.rawValue)",
            name: "AiChatVM"
        )
        model.reasoningEffort = effort
        configWriter.writeReasoningEffort(effort)
    }

    // MARK: - Working directory

    /// 从 `~/.hermes/config.yaml` 重新读取当前工作区目录并更新 UI。
    func loadWorkingDirectory() {
        let cwd = configWriter.readTerminalCwd()
        model.workingDirectory = cwd
        DMLogger.log("loadWorkingDirectory: \(cwd ?? "nil")", name: "AiChatVM")
    }

    /// 设置工作区目录 — 同步更新 `model.workingDirectory` 并写入 `~/.hermes/config.yaml` 的 `terminal.cwd`。
    ///
    /// 官方文档：`terminal.cwd` 指定 terminal 后端执行命令时的工作目录。
    /// - 传入 nil 或空字符串时清除配置，恢复 Hermes 默认行为。
    func setWorkingDirectory(_ path: String?) {
        let normalized = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = normalized?.isEmpty == false ? normalized : nil
        DMLogger.log(
            "setWorkingDirectory: \(model.workingDirectory ?? "nil") -> \(effective ?? "nil")",
            name: "AiChatVM"
        )
        model.workingDirectory = effective
        configWriter.writeTerminalCwd(effective)
    }

    // MARK: - Helpers

    /// 转换本地消息为 gateway 消息格式 — 对齐 Flutter `_buildGatewayMessages`。
    ///
    /// 若用户设置了工作区目录，每次请求前额外插入一条 system 消息，
    /// 显式告知 Hermes 当前工作区，确保 terminal / file 工具在该目录下操作。
    private func buildGatewayMessages(_ messages: [ChatMessage]) -> [GatewayChatMessage] {
        var gwMessages: [GatewayChatMessage] = []

        if let cwd = model.workingDirectory, !cwd.isEmpty {
            let workspacePrompt = """
                当前工作区目录：\(cwd)。
                请将该目录作为本次对话的工作区（workspace），
                后续所有涉及文件、终端命令的操作都基于该目录进行。
                """
            gwMessages.append(GatewayChatMessage(role: "system", content: workspacePrompt))
            DMLogger.log(
                "[DEBUG] buildGatewayMessages: injected workspace system message, cwd=\(cwd)",
                name: "AiChatVM"
            )
        }

        gwMessages.append(contentsOf: messages.map { m in
            let role: String
            switch m.sender {
            case .user:  role = "user"
            case .tool:  role = "tool"
            case .pet:   role = "assistant"
            }
            return GatewayChatMessage(role: role, content: m.text)
        })

        return gwMessages
    }

    /// 错误处理 — 对齐 Flutter `_handleError`。
    private func handleError(_ message: String) {
        DMLogger.log(
            "[DEBUG] _handleError: message=\"\(message)\" " +
            "messagesCount=\(model.messages.count) " +
            "streamBufferLength=\(streamBuffer.count) " +
            "sessionId=\(model.sessionId ?? "nil")",
            name: "AiChatVM"
        )
        model.isLoading = false
        model.connectionState = .error
        model.errorMessage = message
        model.streamingContent = nil
        streamBuffer = ""

        // 错误 → 收回灵动岛工作态
        if hasStartedWorking {
            hasStartedWorking = false
            DynamicNotchManager.shared.stopWorking()
        }
    }

    /// 格式化当前时间为 `HH:mm` — 对齐 Flutter `_nowTime`。
    private func nowTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    /// 安全地将任意值转为 String — 对齐 Flutter `_castToString`。
    ///
    /// 处理 JSON 解析后 `id` / `role` 等字段可能为 Int / NSNumber 的情况。
    private func castToString(_ value: Any?) -> String? {
        guard let value = value else { return nil }
        if let s = value as? String { return s }
        return String(describing: value)
    }
}
