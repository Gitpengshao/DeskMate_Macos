import Foundation
import SwiftUI
import Combine

/// AI 对话页面 ViewModel — 对齐 Flutter `AiChatViewModel`（Riverpod Notifier）。
///
/// MVVM：管理 `model: AiChatModel` 单一状态源，
    /// 通过 `@Published` 通知 SwiftUI 视图刷新。
    @MainActor
    final class AiChatViewModel: ObservableObject {

    /// 全局共享实例，供语音快捷键等需要在控制台未打开时操作聊天状态的模块使用。
    static let shared = AiChatViewModel()

    /// 使用默认值并在声明处初始化，避免 `init` 中 `self.model = ...` 触发 `objectWillChange`，
    /// 从而减少 `@StateObject` 创建时的 "Modifying state during view update" 警告。
    /// 具体的 `reasoningEffort`、`workingDirectory`、`currentModel` 等由 `setupInitialConfigIfNeeded`
    /// 在页面 `onAppear` 或外部首次需要时延迟填充。
    @Published var model: AiChatModel = AiChatModel()

    /// 与 Flutter `hermesServiceProvider` 等价的依赖注入入口；
    /// 默认指向 `127.0.0.1:8642`。
    private let gateway: GatewayClient
    private let chatService: ChatService
    /// 读取 `~/.hermes/config.yaml` 中默认模型 — 驱动 header 徽标显示。
    private let modelConfigService: ModelConfigService

    /// 当前 ViewModel 对应的 Hermes profile；nil 表示默认 profile。
    let profile: String?

    /// 读取 / 写入配置 — 始终与当前 Gateway 运行的 profile 对齐。
    ///
    /// 官方文档明确区分 profile 与 workspace：
    /// `terminal.cwd` 必须写入 Gateway 实际使用的 profile 的 `config.yaml`，
    /// 否则工作区不会生效（文件会创建到默认 `~/.hermes` 或其他目录）。
    private let configWriter: HermesConfigWriter

    /// SSE 流缓冲（与 Flutter `_streamBuffer` 等价）。
    private var streamBuffer: String = ""

    /// 流式过程中累积的非文本内容块：toolCall、fileChange、observation。
    private var streamingToolBlocks: [ContentBlock] = []

    /// 流式中累积的 reasoning 文本（来自 delta.reasoning_content）。
    private var streamingReasoningBuffer: String = ""

    /// 流式中累积的 role=tool 结果文本（Hermes 可能分段返回）。
    private var streamingToolResultBuffer: String = ""

    /// 灵动岛工作态是否已触发 — 首个 deltaChunk 时设为 true，结束后复位
    private var hasStartedWorking: Bool = false

    /// 本地语音识别管理器。
    private let speechManager = SpeechRecognitionManager.shared

    /// 标记是否已完成初始配置填充，避免重复读取文件。
    private var hasSetupInitialConfig = false

    init(
        gateway: GatewayClient? = nil,
        modelConfigService: ModelConfigService? = nil,
        configWriter: HermesConfigWriter? = nil,
        profile: String? = nil,
        petEmoji: String = "🐱",
        petNameKey: String = "petNameHuahua"
    ) {
        // 在 @MainActor 隔离的 init 体内构造默认值，
        // 避免在默认参数（nonisolated 上下文）中调用 main actor-isolated 初始化器。
        // 使用 GatewayClient.shared 以便 HermesGatewayService 启动后注入的 apiKey 生效。
        self.profile = profile
        let resolvedGateway = gateway ?? GatewayClient.shared
        self.gateway = resolvedGateway
        self.chatService = ChatService(gatewayClient: resolvedGateway)
        self.modelConfigService = modelConfigService ?? ModelConfigService(hermesHome: AppConstants.resolveHermesHome(for: profile))
        // 初始读取使用当前 profile（通常是 nil，即默认 `~/.hermes`）；
        // 页面 onAppear 会再次刷新，确保 Gateway 启动后拿到最新值。
        let writer = configWriter ?? HermesConfigWriter.forProfile(profile)
        self.configWriter = writer

        setupSpeechRecognition()

        // 在 init 中直接填充初始配置。model 是 @Published，但在 init 体内赋值不会触发
        // objectWillChange，因此不会导致 "Modifying state during view update"。
        // 把 loadCurrentModel / loadWorkingDirectory 也合并到这里，避免在 onAppear 中重复触发视图重建。
        setupInitialConfigIfNeeded(petEmoji: petEmoji, petNameKey: petNameKey)
    }

    /// 从 config.yaml 同步当前推理强度、工作区、默认模型等初始值。
    /// 设计为幂等，只在 init 中调用一次。
    func setupInitialConfigIfNeeded(petEmoji: String = "🐱", petNameKey: String = "petNameHuahua") {
        guard !hasSetupInitialConfig else { return }
        hasSetupInitialConfig = true
        let loaded = configWriter.readReasoningEffort()
        let cwd = configWriter.readTerminalCwd()
        model.petEmoji = petEmoji
        model.petNameKey = petNameKey
        model.reasoningEffort = loaded
        model.workingDirectory = cwd
        DMLogger.log("[AiChatVM] setupInitialConfigIfNeeded: reasoning=\(loaded.rawValue) cwd=\(cwd ?? "nil")", name: "AiChatVM")

        // 默认模型：后台读取，避免阻塞 init；结果返回后通过 @MainActor Task 异步更新
        // model.currentModel，避免在视图更新周期中触发 objectWillChange。
        Task { [weak self] in
            guard let self = self else { return }
            let info = await self.modelConfigService.readCurrentModel()
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.model.currentModel = info
                DMLogger.log(
                    "setupInitialConfigIfNeeded: currentModel=\(info?.fullName ?? "nil")",
                    name: "AiChatVM"
                )
            }
        }
    }

    /// 绑定本地语音识别回调。
    private func setupSpeechRecognition() {
        speechManager.onTranscription = { [weak self] text, isFinal in
            guard let self = self else { return }
            self.model.voiceTranscribedText = text
            self.model.inputText = text
            self.model.voiceError = nil

            if isFinal {
                self.model.isRecording = false
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self.sendMessage()
                }
            } else {
                self.model.isRecording = true
            }
        }

        speechManager.onError = { [weak self] message in
            guard let self = self else { return }
            self.model.isRecording = false
            self.model.voiceError = message
            DMLogger.log("Speech recognition error: \(message)", name: "AiChatVM")
        }
    }

    // MARK: - Input

    /// 更新输入框文本 — 对齐 Flutter `updateInput`。
    func updateInput(_ text: String) {
        model.inputText = text
    }

    /// 添加选中的文件/目录引用到输入框。
    func addReference(path: String, isDirectory: Bool) {
        DMLogger.log(
            "addReference: path=\(path) isDirectory=\(isDirectory)",
            name: "AiChatViewModel"
        )
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

    // MARK: - Image attachments

    /// 添加图片附件到输入区。
    func addImageAttachment(_ attachment: ChatImageAttachment) {
        guard !model.pendingImageAttachments.contains(where: { $0.id == attachment.id }) else { return }
        model.pendingImageAttachments.append(attachment)
        DMLogger.log(
            "addImageAttachment: id=\(attachment.id) displayName=\(attachment.displayName)",
            name: "AiChatViewModel"
        )
    }

    /// 移除指定图片附件。
    func removeImageAttachment(_ id: String) {
        model.pendingImageAttachments.removeAll { $0.id == id }
    }

    /// 清空全部待发送图片。
    func clearImageAttachments() {
        model.pendingImageAttachments = []
    }

    // MARK: - Voice input

    /// 切换麦克风录音状态；识别完成后会自动调用 `sendMessage` 发送文本。
    func toggleVoiceRecording() {
        guard !model.isStreaming else { return }

        if model.isRecording {
            speechManager.stopRecording()
        } else {
            model.voiceError = nil
            model.voiceTranscribedText = ""
            speechManager.startRecording()
        }
    }

    /// 取消当前录音并清空临时文本。
    func cancelVoiceRecording() {
        speechManager.cancelRecording()
        model.isRecording = false
        model.voiceTranscribedText = ""
    }

    // MARK: - Send

    /// 发送当前输入文本并启动 SSE 流 — 对齐 Flutter `sendMessage`。
    func sendMessage() {
        let text = model.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // 将引用路径拼接到实际发送的文本中
        let refText = model.referenceText
        let pendingImages = model.pendingImageAttachments
        let hasImages = !pendingImages.isEmpty
        guard (!text.isEmpty || !refText.isEmpty || hasImages), !model.isStreaming else { return }

        let fullText: String
        if refText.isEmpty {
            fullText = text
        } else if text.isEmpty {
            fullText = refText
        } else {
            fullText = text + " " + refText
        }

        // 1. 构造用户消息并加入列表（文本 + 图片附件）
        let userMsg = ChatMessage(
            id: String(Int(Date().timeIntervalSince1970 * 1000)),
            sender: .user,
            text: fullText,
            timestamp: nowTime(),
            imageAttachments: pendingImages
        )

        DMLogger.log(
            "[DEBUG] sendMessage: adding userMsg id=\(userMsg.id), " +
            "current messages count=\(model.messages.count)",
            name: "AiChatVM"
        )

        model.messages.append(userMsg)
        model.inputText = ""
        model.selectedReferences = []
        model.pendingImageAttachments = []
        model.isLoading = true
        model.connectionState = .connecting
        model.errorMessage = nil
        model.streamingContent = nil
        model.streamingBlocks = []
        model.toolProgressEvents = []
        streamingToolBlocks = []
        streamingReasoningBuffer = ""
        streamingToolResultBuffer = ""

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

    /// 把累积的 role=tool 结果文本解析为 observation / fileChange 块。
    private func flushToolResultBuffer() {
        guard !streamingToolResultBuffer.isEmpty else { return }
        let blocks = ChatContentParser.parseToolMessage(content: streamingToolResultBuffer)
        streamingToolBlocks.append(contentsOf: blocks)
        DMLogger.log(
            "[DEBUG] flushToolResultBuffer: parsed \(blocks.count) blocks from len=\(streamingToolResultBuffer.count)",
            name: "AiChatVM"
        )
        streamingToolResultBuffer = ""
    }

    /// 根据当前 streamBuffer 与累积的 reasoning / tool 块重建流式内容块。
    private func rebuildStreamingBlocks() {
        var allBlocks: [ContentBlock] = []

        if !streamingReasoningBuffer.isEmpty {
            allBlocks.append(.reasoning(text: streamingReasoningBuffer, isPending: true))
        }

        let textBlocks = ChatContentParser.parseContentBlocks(
            from: streamBuffer,
            streaming: true
        )
        allBlocks.append(contentsOf: textBlocks)
        allBlocks.append(contentsOf: streamingToolBlocks)

        model.streamingBlocks = allBlocks
        DMLogger.log(
            "[DEBUG] rebuildStreamingBlocks: bufferLen=\(streamBuffer.count) " +
            "textBlocks=\(textBlocks.count) toolBlocks=\(streamingToolBlocks.count) " +
            "total=\(allBlocks.count)",
            name: "AiChatVM"
        )
        for (i, block) in allBlocks.enumerated() {
            DMLogger.log(
                "[DEBUG] block[\(i)]: \(blockDescription(block))",
                name: "AiChatVM"
            )
        }
    }

    private func blockDescription(_ block: ContentBlock) -> String {
        switch block {
        case .text(let text):
            return "text(len=\(text.count))"
        case .reasoning(let text, let isPending):
            return "reasoning(pending=\(isPending), len=\(text.count))"
        case .toolCall(let tc):
            return "toolCall(\(tc.name), argsLen=\(tc.displayArguments.count))"
        case .observation(let obs):
            return "observation(\(obs.toolName), status=\(obs.status.rawValue), textLen=\(obs.text.count))"
        case .fileChange(let fc):
            return "fileChange(\(fc.operation.rawValue): \(fc.path))"
        }
    }

    /// 处理单个流事件 — 对齐 Flutter `_onStreamEvent`。
    private func onStreamEvent(_ event: ChatStreamEvent) {
        switch event {
        case .sessionCreated(let sessionId):
            DMLogger.log("[DEBUG] SessionCreated: \(sessionId)", name: "AiChatVM")
            model.sessionId = sessionId

        case .reasoningChunk(let text):
            streamingReasoningBuffer.append(text)
            DMLogger.log(
                "[DEBUG] ReasoningChunk: len=\(text.count) total=\(streamingReasoningBuffer.count)",
                name: "AiChatVM"
            )
            rebuildStreamingBlocks()
            model.connectionState = .streaming

        case .deltaChunk(let text):
            // 首个 deltaChunk 触发灵动岛工作态（与 think 动画结束同步）
            if !hasStartedWorking {
                hasStartedWorking = true
                DynamicNotchManager.shared.startWorking()
            }
            // 收到 assistant 正文时，先把之前累积的 role=tool 结果 flush 成块
            flushToolResultBuffer()
            streamBuffer.append(text)
            DMLogger.log(
                "[DEBUG] DeltaChunk: text=\"\(text)\", buffer length=\(streamBuffer.count)",
                name: "AiChatVM"
            )
            model.streamingContent = streamBuffer
            rebuildStreamingBlocks()
            model.connectionState = .streaming

        case .toolResultChunk(let text):
            streamingToolResultBuffer.append(text)
            DMLogger.log(
                "[DEBUG] ToolResultChunk: len=\(text.count) total=\(streamingToolResultBuffer.count)",
                name: "AiChatVM"
            )
            model.connectionState = .streaming

        case .toolCall(let toolCallId, let name, let arguments, let displayText):
            DMLogger.log(
                "[DEBUG] ToolCall: id=\(toolCallId ?? "nil") name=\(name) displayText=\(displayText)",
                name: "AiChatVM"
            )
            let id = toolCallId ?? "\(name)-\(Date().timeIntervalSince1970)"
            let displayArgs: String
            if let data = try? JSONSerialization.data(withJSONObject: arguments, options: .sortedKeys),
               let json = String(data: data, encoding: .utf8) {
                displayArgs = json
            } else {
                displayArgs = String(describing: arguments)
            }
            streamingToolBlocks.append(.toolCall(ToolCallBlock(
                id: id,
                name: name,
                arguments: arguments,
                displayArguments: displayArgs
            )))
            let fileChanges = ChatContentParser.detectFileChanges(toolName: name, arguments: arguments)
            streamingToolBlocks.append(contentsOf: fileChanges.map { .fileChange($0) })
            rebuildStreamingBlocks()

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

            // 工具完成或失败时生成 observation 块，便于在 assistant 消息内展示结果。
            if event.status == .completed || event.status == .failed {
                let observationId = event.toolCallId ?? event.id
                streamingToolBlocks.removeAll { block in
                    if case .observation(let obs) = block, obs.id == observationId { return true }
                    return false
                }
                streamingToolBlocks.append(.observation(ObservationBlock(
                    id: observationId,
                    toolName: event.tool,
                    text: event.label,
                    status: event.status
                )))
                rebuildStreamingBlocks()
            }
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

        // 组装最终 assistant 消息的内容块
        // 流式末尾可能没有后续 delta，先把累积的 role=tool 结果 flush 成块
        flushToolResultBuffer()

        var finalContentBlocks: [ContentBlock] = []
        if !streamingReasoningBuffer.isEmpty {
            finalContentBlocks.append(.reasoning(text: streamingReasoningBuffer, isPending: false))
        }
        let finalTextBlocks = ChatContentParser.parseContentBlocks(
            from: fullContent,
            streaming: false
        )
        finalContentBlocks.append(contentsOf: finalTextBlocks)
        finalContentBlocks.append(contentsOf: streamingToolBlocks)

        // 加入助手消息
        let assistantMsg = ChatMessage(
            id: "\(Int(Date().timeIntervalSince1970 * 1000))_pet",
            sender: .pet,
            text: fullContent.isEmpty ? "..." : fullContent,
            timestamp: nowTime(),
            contentBlocks: finalContentBlocks
        )

        DMLogger.log(
            "[DEBUG] _onStreamDone: adding assistantMsg id=\(assistantMsg.id), " +
            "text length=\(assistantMsg.text.count), blocks=\(finalContentBlocks.count)",
            name: "AiChatVM"
        )

        model.messages.append(assistantMsg)

        model.streamingContent = nil
        model.streamingBlocks = []
        model.toolProgressEvents = []
        streamingToolBlocks = []
        streamingReasoningBuffer = ""
        streamingToolResultBuffer = ""
        model.isLoading = false
        model.connectionState = .completed

        // 流结束 → 收回灵动岛工作态
        if hasStartedWorking {
            hasStartedWorking = false
            DynamicNotchManager.shared.stopWorking()
        }

        // 后台刷新今日汇总，供控制台打开时灵动岛展示
        DynamicNotchManager.shared.refreshTodayStats()

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

            // 后端不保存图片数据，按 user 消息顺序把本地图片附件与后端消息 ID 关联缓存
            DMLogger.log(
                "[DEBUG] _syncFromDatabase: syncing image attachments, localMessages=\(self.model.messages.count)",
                name: "AiChatVM"
            )
            self.syncImageAttachments(
                localMessages: self.model.messages,
                syncedMessages: synced,
                sessionId: sessionId
            )

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
            let partialBlocks = ChatContentParser.parseContentBlocks(from: partialContent, streaming: false)
                + streamingToolBlocks
            let assistantMsg = ChatMessage(
                id: "\(Int(Date().timeIntervalSince1970 * 1000))_pet",
                sender: .pet,
                text: partialContent,
                timestamp: nowTime(),
                contentBlocks: partialBlocks
            )
            model.messages.append(assistantMsg)
            DMLogger.log(
                "[DEBUG] stopStream: preserved partial message, " +
                "text length=\(assistantMsg.text.count), blocks=\(partialBlocks.count)",
                name: "AiChatVM"
            )
        }

        model.streamingContent = nil
        model.streamingBlocks = []
        model.toolProgressEvents = []
        streamingToolBlocks = []
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

            // 诊断：打印每条历史消息的原始字段，确认图片/多模态内容格式
            for (i, m) in raw!.enumerated() {
                self.logSessionMessage(m, index: i)
            }

            let sessionIdForCache = sessionId
            var messages: [ChatMessage] = []
            // 记录包含 [screenshot] 占位符但缓存未命中的消息，用于后续从文件系统兜底
            var unresolvedPlaceholders: [(index: Int, messageId: String, date: Date)] = []

            for (index, m) in raw!.enumerated() {
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
                var message = ChatMessage(
                    id: id,
                    sender: sender,
                    text: content,
                    timestamp: self.nowTime()
                )
                switch sender {
                case .pet:
                    let reasoning = self.castToString(m["reasoning"])
                        ?? self.castToString(m["reasoning_content"])
                        ?? ""
                    let blocks = ChatContentParser.parseAssistantMessage(
                        content: content,
                        reasoning: reasoning,
                        toolCalls: m["tool_calls"]
                    )
                    message.contentBlocks = blocks
                    DMLogger.log(
                        "[DEBUG] loadSession parsed assistant message id=\(id) " +
                        "contentLen=\(content.count) reasoningLen=\(reasoning.count) blocks=\(blocks.count)",
                        name: "AiChatVM"
                    )
                case .tool:
                    let blocks = ChatContentParser.parseToolMessage(content: content)
                    message.contentBlocks = blocks
                    DMLogger.log(
                        "[DEBUG] loadSession parsed tool message id=\(id) " +
                        "contentLen=\(content.count) blocks=\(blocks.count)",
                        name: "AiChatVM"
                    )
                case .user:
                    break
                }
                // 后端不保存图片数据，从历史缓存中按消息 ID 还原图片附件
                if sender == .user, self.isImagePlaceholder(content) {
                    let attachments = ImageAttachmentCache.shared.attachments(
                        forSessionId: sessionIdForCache,
                        messageId: id
                    )
                    message.imageAttachments = attachments
                    if attachments.isEmpty, let messageDate = self.messageDate(from: m) {
                        unresolvedPlaceholders.append((index: index, messageId: id, date: messageDate))
                    } else if !attachments.isEmpty {
                        DMLogger.log(
                            "[DEBUG] loadSession image cache hit: " +
                            "sessionId=\(sessionIdForCache) messageId=\(id) count=\(attachments.count)",
                            name: "AiChatVM"
                        )
                    }
                    // 无论缓存是否命中，都移除占位符文本，避免 UI 直接显示 [screenshot]
                    message.text = content
                        .replacingOccurrences(of: "[screenshot]", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                messages.append(message)
            }

            // 缓存未命中时，按消息时间戳从 ~/.hermes/images/ 找回图片。
            // 从新到旧处理，避免较早消息占用较晚消息的截图。
            var usedImagePaths = Set<String>()
            for info in unresolvedPlaceholders.sorted(by: { $0.date > $1.date }) {
                if let fallback = ImageAttachmentManager.shared.resolveMissingAttachment(
                    messageTimestamp: info.date,
                    excludedPaths: usedImagePaths
                ) {
                    messages[info.index].imageAttachments = [fallback]
                    if let localPath = fallback.localPath {
                        usedImagePaths.insert(localPath)
                    }
                    ImageAttachmentCache.shared.saveAttachments(
                        [fallback],
                        sessionId: sessionIdForCache,
                        messageId: info.messageId
                    )
                    DMLogger.log(
                        "[DEBUG] loadSession fallback image resolved: " +
                        "sessionId=\(sessionIdForCache) messageId=\(info.messageId) " +
                        "path=\(fallback.localPath ?? "nil")",
                        name: "AiChatVM"
                    )
                } else {
                    DMLogger.log(
                        "[DEBUG] loadSession fallback image not found: " +
                        "sessionId=\(sessionIdForCache) messageId=\(info.messageId) " +
                        "timestamp=\(info.date)",
                        name: "AiChatVM"
                    )
                }
            }

            DMLogger.log(
                "[DEBUG] loadSession: loaded \(messages.count) messages for \(sessionId)",
                name: "AiChatVM"
            )

            // 后端可能不返回 additions/deletions，用历史消息里的 read/write 内容补全
            ChatContentParser.fillMissingLineCounts(for: &messages)

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
        model.pendingImageAttachments = []
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
            let info = await self.modelConfigService.readCurrentModel()

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

        // terminal.cwd 修改后必须重启 Gateway，Hermes 才会重新读取 config.yaml 并生效。
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let result = await HermesGatewayService.shared.restartGateway(for: self.profile)
            if result == nil {
                self.model.errorMessage = "工作区已更新，但 Hermes Gateway 重启失败，新工作区可能未生效"
                DMLogger.log(
                    "setWorkingDirectory: Gateway 重启失败 profile=\(self.profile ?? "default")",
                    name: "AiChatVM"
                )
            } else {
                self.model.errorMessage = nil
                DMLogger.log(
                    "setWorkingDirectory: Gateway 重启成功 port=\(result!.port)",
                    name: "AiChatVM"
                )
            }
        }
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

            // 用户消息附带图片时，使用 OpenAI 多模态内容数组格式。
            if role == "user", !m.imageAttachments.isEmpty {
                DMLogger.log(
                    "[DEBUG] buildGatewayMessages: user msg id=\(m.id) " +
                    "images=\(m.imageAttachments.count) textLen=\(m.text.count) " +
                    "firstImageDataUrlLen=\(m.imageAttachments.first?.dataUrl.count ?? 0)",
                    name: "AiChatVM"
                )
                var parts: [ChatContentPart] = []
                if !m.text.isEmpty {
                    parts.append(.text(m.text))
                }
                for attachment in m.imageAttachments {
                    parts.append(.imageUrl(attachment.dataUrl))
                }
                return GatewayChatMessage(role: role, parts: parts)
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

    /// 将本地用户消息的图片附件与后端同步回来的消息 ID 关联并缓存。
    ///
    /// Hermes 后端不保存图片数据，只保留 `[screenshot]` 等占位文本。
    /// 这里按 user 消息出现顺序一一配对，把本地图片附件保存到缓存。
    private func syncImageAttachments(
        localMessages: [ChatMessage],
        syncedMessages: [SyncedMessage],
        sessionId: String
    ) {
        let localUserMessages = localMessages.filter { $0.sender == .user }
        let syncedUserMessages = syncedMessages.filter { $0.role == "user" }
        guard !localUserMessages.isEmpty else { return }

        DMLogger.log(
            "[DEBUG] syncImageAttachments: sessionId=\(sessionId) " +
            "localUser=\(localUserMessages.count) syncedUser=\(syncedUserMessages.count)",
            name: "AiChatVM"
        )

        for (index, local) in localUserMessages.enumerated() {
            guard index < syncedUserMessages.count else {
                DMLogger.log(
                    "[DEBUG] syncImageAttachments: index \(index) out of syncedUser range (\(syncedUserMessages.count))",
                    name: "AiChatVM"
                )
                break
            }
            guard !local.imageAttachments.isEmpty else {
                DMLogger.log(
                    "[DEBUG] syncImageAttachments: local user msg \(local.id) has no attachments",
                    name: "AiChatVM"
                )
                continue
            }
            let synced = syncedUserMessages[index]
            DMLogger.log(
                "[DEBUG] syncImageAttachments: saving local msg \(local.id) -> synced id \(synced.id) count=\(local.imageAttachments.count)",
                name: "AiChatVM"
            )
            ImageAttachmentCache.shared.saveAttachments(
                local.imageAttachments,
                sessionId: sessionId,
                messageId: synced.id
            )
        }
    }

    /// 判断后端返回的文本是否包含图片占位符。
    private func isImagePlaceholder(_ text: String) -> Bool {
        text.contains("[screenshot]")
    }

    /// 从后端原始消息中解析时间戳，支持秒/毫秒级 Unix 时间戳和 ISO8601 字符串。
    private func messageDate(from raw: [String: Any]) -> Date? {
        let timestamp = raw["timestamp"]
        if let date = timestamp as? Date { return date }
        if let interval = timestamp as? TimeInterval {
            if interval > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: interval / 1000)
            }
            if interval > 1_000_000_000 {
                return Date(timeIntervalSince1970: interval)
            }
        }
        if let number = timestamp as? NSNumber {
            let interval = number.doubleValue
            if interval > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: interval / 1000)
            }
            if interval > 1_000_000_000 {
                return Date(timeIntervalSince1970: interval)
            }
        }
        if let str = timestamp as? String {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: str) { return date }
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: str) { return date }

            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd HH:mm:ss.SSS"
            ]
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            for format in formats {
                formatter.dateFormat = format
                if let date = formatter.date(from: str) { return date }
            }
        }
        return nil
    }

    /// 打印后端返回的单条历史消息原始字段，用于诊断图片/多模态格式。
    private func logSessionMessage(_ m: [String: Any], index: Int) {
        let id = self.castToString(m["id"]) ?? "nil"
        let role = self.castToString(m["role"]) ?? "nil"
        let content = m["content"]
        let contentType = String(describing: type(of: content))
        let contentDesc: String
        if let arr = content as? [Any] {
            let parts = arr.enumerated().map { (idx, item) -> String in
                if let dict = item as? [String: Any] {
                    return "[\(idx)] dict(keys=\(dict.keys.sorted()))"
                } else if let str = item as? String {
                    return "[\(idx)] string(len=\(str.count))"
                } else {
                    return "[\(idx)] \(String(describing: type(of: item)))"
                }
            }.joined(separator: ", ")
            contentDesc = "array(count=\(arr.count), parts=[\(parts)])"
        } else if let str = content as? String {
            contentDesc = "string(len=\(str.count), preview=\(str.prefix(200)))"
        } else {
            contentDesc = "\(contentType): \(String(describing: content).prefix(200))"
        }
        let timestampDesc: String
        if let date = self.messageDate(from: m) {
            timestampDesc = "parsedDate=\(date)"
        } else if let ts = m["timestamp"] {
            timestampDesc = "raw=\(String(describing: ts))"
        } else {
            timestampDesc = "missing"
        }
        DMLogger.log(
            "[DEBUG] loadSession raw[\(index)] id=\(id) role=\(role) " +
            "contentType=\(contentType) content=\(contentDesc) " +
            "timestamp=\(timestampDesc) " +
            "allKeys=\(m.keys.sorted())",
            name: "AiChatVM"
        )
    }

    /// 安全地将任意值转为 String — 对齐 Flutter `_castToString`。
    ///
    /// 处理 JSON 解析后 `id` / `role` 等字段可能为 Int / NSNumber 的情况；
    /// JSON null（NSNull）返回 nil，避免显示成 "nil" 文本。
    private func castToString(_ value: Any?) -> String? {
        guard let value = value else { return nil }
        if value is NSNull { return nil }
        if let s = value as? String { return s }
        return String(describing: value)
    }
}
