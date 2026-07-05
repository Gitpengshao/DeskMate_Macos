import SwiftUI

/// AI 对话主页面 — 整体黑白风格设计。
struct AiChatPage: View {
    @StateObject private var chatVM = AiChatViewModel()
    @StateObject private var sessionVM = SessionListViewModel()
    @State private var searchText = ""
    @State private var inputText = ""
    @State private var showFilePicker = false

    var isDark: Bool = true

    var body: some View {
        ZStack {
            Palette.bgBase.ignoresSafeArea()
            HStack(spacing: 0) {
                if chatVM.model.sidebarVisible {
                    SessionSidebar(
                        sessionVM: sessionVM,
                        activeSessionId: chatVM.model.sessionId,
                        isDark: isDark,
                        searchText: $searchText,
                        onSelect: { id in chatVM.loadSession(id) },
                        onDelete: { id in
                            sessionVM.deleteSession(id)
                            if chatVM.model.sessionId == id {
                                chatVM.newSession()
                            }
                        },
                        onRefresh: { sessionVM.refresh() }
                    )
                }

                chatArea
            }
        }
        .overlay(filePickerOverlay)
        .onAppear {
            sessionVM.loadSessions()
            // 从 ~/.hermes/config.yaml 读取当前默认模型，渲染到 header 徽标。
            chatVM.loadCurrentModel()
            // 从 ~/.hermes/config.yaml 读取当前工作区目录。
            chatVM.loadWorkingDirectory()
            // 兜底消费：用户可能先在工作区窗口添加了引用，再切到 AI 对话页。
            // 用 async 避免 "Modifying state during view update" 警告。
            DispatchQueue.main.async { self.consumePendingReference() }
        }
        .onReceive(WorkspaceReferenceBridge.shared.$pendingReference) { _ in
            // bridge 发布新值时立刻消费，覆盖"AI 对话页已在前台"的场景。
            // ⚠️ onReceive 在 SwiftUI 更新周期中触发，必须 async 到下一帧
            // 才能安全地修改 @Published 状态，否则会触发运行时警告并可能导致
            // 本次 UI 更新丢失。
            DispatchQueue.main.async { self.consumePendingReference() }
        }
    }

    // MARK: - Cross-window reference ingestion

    /// 消费 `WorkspaceReferenceBridge` 中待加入的引用 — 转发给 `chatVM.addReference`。
    ///
    /// 同时把主窗口前置，确保用户能看到引用 chip 已添加。多次相同路径的
    /// 入队会被 `addReference` 内部去重（按 `id == path`）。
    ///
    /// # 防御性校验
    /// 通过 `FileManager` 重新确认 `isDirectory`，防止上游 (`FileTreeView` context menu 等)
    /// 传入错误值导致文件被错误地视为目录。
    private func consumePendingReference() {
        guard let pending = WorkspaceReferenceBridge.shared.pendingReference else { return }

        DMLogger.log(
            "Consume bridge: path=\(pending.path) bridgeIsDir=\(pending.isDirectory)",
            name: "AiChatPage"
        )

        // 用 FileManager 重新确认 isDirectory，消除上游传入错误值的可能性
        var isDir: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: pending.path, isDirectory: &isDir)
        let actualIsDir = fileExists ? isDir.boolValue : pending.isDirectory

        DMLogger.log(
            "Consume bridge: fileExists=\(fileExists) fmIsDir=\(actualIsDir) → using=\(actualIsDir)",
            name: "AiChatPage"
        )

        chatVM.addReference(path: pending.path, isDirectory: actualIsDir)
        WorkspaceReferenceBridge.shared.consume()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - File picker

    @ViewBuilder
    private var filePickerOverlay: some View {
        if showFilePicker, let cwd = chatVM.model.workingDirectory, !cwd.isEmpty {
            WorkspaceFilePicker(
                workingDirectory: cwd,
                onSelect: { path, isDirectory in
                    // 移除触发 picker 的尾部 `#`
                    if inputText.hasSuffix("#") {
                        inputText.removeLast()
                        chatVM.updateInput(inputText)
                    }
                    // 拼装为完整绝对路径
                    let fullPath = (chatVM.model.workingDirectory! as NSString).appendingPathComponent(path)
                    chatVM.addReference(path: fullPath, isDirectory: isDirectory)
                    showFilePicker = false
                },
                onCancel: {
                    showFilePicker = false
                }
            )
        }
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        VStack(spacing: 0) {
            ChatHeader(
                sessionTitle: chatVM.model.sessionTitle,
                sessionId: chatVM.model.sessionId,
                sidebarVisible: chatVM.model.sidebarVisible,
                isDark: isDark,
                onToggleSidebar: { chatVM.toggleSidebar() },
                currentModel: chatVM.model.currentModel,
                workingDirectory: chatVM.model.workingDirectory
            )

            if chatVM.model.isLoading && !chatVM.model.isStreaming {
                loadingIndicator
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .background(Palette.bgBase)
            }

            if let err = chatVM.model.errorMessage {
                errorBanner(err)
            }

            messagesArea

            InputBar(
                text: $inputText,
                selectedReferences: $chatVM.model.selectedReferences,
                isStreaming: chatVM.model.isStreaming,
                petNameKey: chatVM.model.petNameKey,
                isDark: isDark,
                reasoningEffort: chatVM.model.reasoningEffort,
                workingDirectory: chatVM.model.workingDirectory,
                currentProfile: HermesGatewayService.shared.currentProfile,
                onSend: {
                    chatVM.updateInput(inputText)
                    chatVM.sendMessage()
                    inputText = ""
                },
                onInputChange: { chatVM.updateInput($0) },
                onReasoningEffortChange: { chatVM.setReasoningEffort($0) },
                onWorkingDirectoryChange: { chatVM.setWorkingDirectory($0) },
                onStop: { chatVM.stopStream() },
                onRemoveReference: { chatVM.removeReference($0) },
                showFilePicker: $showFilePicker
            )
        }
        .background(Palette.bgBase)
    }

    // MARK: - Messages area

    @ViewBuilder
    private var messagesArea: some View {
        let displayMessages = chatVM.model.messages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let isStreaming = chatVM.model.isStreaming || !chatVM.model.toolProgressEvents.isEmpty

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(displayMessages) { msg in
                        messageBubble(for: msg)
                            .id(msg.id)
                    }
                    if isStreaming {
                        streamingBubble.id("streaming")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            .onChange(of: displayMessages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(isStreaming ? "streaming" : (displayMessages.last?.id ?? "streaming"), anchor: .bottom)
                }
            }
            .onChange(of: chatVM.model.streamingContent) { oldValue, newValue in
                DMLogger.log(
                    "AiChatPage streamingContent changed: " +
                    "\(oldValue?.count ?? 0) -> \(newValue?.count ?? 0)",
                    name: "AiChatPage"
                )
                if isStreaming {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatVM.model.toolProgressEvents.count) { _, _ in
                if isStreaming {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(for msg: ChatMessage) -> some View {
        switch msg.sender {
        case .pet:
            PetMessageBubble(
                message: msg,
                petEmoji: chatVM.model.petEmoji,
                petNameKey: chatVM.model.petNameKey,
                isDark: isDark,
                isStreaming: false,
                toolProgressEvents: []
            )
        case .user:
            UserMessageBubble(message: msg, isDark: isDark)
        case .tool:
            ToolMessageBubble(message: msg, isDark: isDark)
        }
    }

    private var streamingBubble: some View {
        PetMessageBubble(
            message: ChatMessage(
                id: "streaming",
                sender: .pet,
                text: chatVM.model.streamingContent ?? "",
                timestamp: nowTime()
            ),
            petEmoji: chatVM.model.petEmoji,
            petNameKey: chatVM.model.petNameKey,
            isDark: isDark,
            isStreaming: true,
            toolProgressEvents: chatVM.model.toolProgressEvents
        )
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundColor(Palette.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(2)
            Spacer()
            Button(action: { chatVM.retry() }) {
                Text("重试")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.inverseInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Palette.inverse)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.bgPanel)
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Helpers

    private var loadingIndicator: some View {
        ProgressView()
            .scaleEffect(0.7)
            .tint(Palette.textPrimary)
    }

    private func nowTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

// MARK: - Palette (Monochrome)

private enum Palette {
    static let bgBase      = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let bgElevated  = Color(red: 0.078, green: 0.078, blue: 0.078)
    static let bgHover     = Color(red: 0.110, green: 0.110, blue: 0.110)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
    static let inverse     = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let inverseInk  = Color(red: 0.000, green: 0.000, blue: 0.000)
}
