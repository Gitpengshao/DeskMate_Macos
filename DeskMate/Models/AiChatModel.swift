import Foundation

/// 消息发送者类型 — 对齐 Flutter `MessageSender`。
enum MessageSender: String, Codable, Equatable {
    case pet       // 宠物/AI 助手
    case user
    case tool
}

/// SSE 流连接状态 — 对齐 Flutter `ChatConnectionState`。
enum ChatConnectionState: String, Codable, Equatable {
    case idle
    case connecting
    case streaming
    case completed
    case error
}

/// 选中的文件/目录引用项 — 在输入框中显示为 chip，发送时转为路径文本。
struct ReferenceItem: Identifiable, Equatable, Codable {
    let id: String
    /// 文件的绝对路径，如 `/Users/xxx/project/src/main.swift`。
    let path: String
    /// 是否为目录。
    let isDirectory: Bool
    /// UI 显示名（取路径最后一段）。
    var displayName: String { (path as NSString).lastPathComponent }
}

/// 聊天消息中附带的图片 — 以 base64 data URL 形式存储，对齐 Hermes 视觉内容格式。
struct ChatImageAttachment: Identifiable, Equatable, Codable {
    let id: String
    /// `data:image/png;base64,...` 编码后的图像数据。
    let dataUrl: String
    /// 本地缓存路径（如保存到 `~/.hermes/images/`）。
    let localPath: String?
    /// 原始文件名或截图时生成的时间戳文件名，用于 UI 显示。
    let displayName: String
}

/// AI 回复内容块的类型 — 参考 hermes-studio ContentBlock 概念，把一次 assistant 消息拆成多段。
enum ContentBlock: Identifiable, Equatable {
    /// 普通正文文本（Markdown）。
    case text(String)
    /// 思考过程；`isPending` 表示流式中尚未闭合 <think> 标签。
    case reasoning(text: String, isPending: Bool)
    /// 工具调用（action）。
    case toolCall(ToolCallBlock)
    /// 工具执行结果（observation）。
    case observation(ObservationBlock)
    /// 文件改动摘要。
    case fileChange(FileChangeBlock)

    var id: String {
        switch self {
        case .text(let text):
            return "text-\(text.hashValue)"
        case .reasoning(let text, let isPending):
            return "reasoning-\(isPending)-\(text.hashValue)"
        case .toolCall(let block):
            return "toolCall-\(block.id)"
        case .observation(let block):
            return "observation-\(block.id)"
        case .fileChange(let block):
            return "fileChange-\(block.id)"
        }
    }
}

/// 工具调用内容块 —— action。
struct ToolCallBlock: Identifiable, Equatable {
    let id: String
    let name: String
    let arguments: [String: Any]
    /// 用于 UI 展示的参数 JSON 字符串。
    let displayArguments: String

    static func == (lhs: ToolCallBlock, rhs: ToolCallBlock) -> Bool {
        lhs.id == rhs.id
        && lhs.name == rhs.name
        && lhs.displayArguments == rhs.displayArguments
    }
}

/// 工具执行结果内容块 —— observation。
struct ObservationBlock: Identifiable, Equatable {
    let id: String
    let toolName: String
    let text: String
    let status: ToolProgressStatus
}

/// 文件改动操作类型。
enum FileChangeOperation: String, Codable, Equatable {
    case add
    case delete
    case modify
}

/// 文件改动内容块。
struct FileChangeBlock: Identifiable, Equatable {
    let id: String
    let path: String
    let operation: FileChangeOperation
    /// 新增行数（后端提供时展示为 +N）。
    let additions: Int?
    /// 删除行数（后端提供时展示为 -N）。
    let deletions: Int?
    /// 工具调用参数中的新文件内容，用于在工具结果没有返回行数时本地 diff 计算。
    let newContent: String?
}

/// 单条聊天消息 — 对齐 Flutter `ChatMessage`。
struct ChatMessage: Identifiable, Equatable, Codable {
    let id: String
    let sender: MessageSender
    var text: String
    let timestamp: String
    var toolCall: String? // 例如：'🔧 已调用: weather_search(location="Beijing")'
    /// 用户消息附带的图片（多模态视觉输入）。
    var imageAttachments: [ChatImageAttachment] = []
    /// assistant 消息的 UI 内容块；不参与持久化，加载时从 `text` 重新解析。
    var contentBlocks: [ContentBlock] = []

    private enum CodingKeys: String, CodingKey {
        case id, sender, text, timestamp, toolCall, imageAttachments
    }

    init(
        id: String,
        sender: MessageSender,
        text: String,
        timestamp: String,
        toolCall: String? = nil,
        imageAttachments: [ChatImageAttachment] = [],
        contentBlocks: [ContentBlock] = []
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.toolCall = toolCall
        self.imageAttachments = imageAttachments
        self.contentBlocks = contentBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.sender = try container.decode(MessageSender.self, forKey: .sender)
        self.text = try container.decode(String.self, forKey: .text)
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
        self.toolCall = try container.decodeIfPresent(String.self, forKey: .toolCall)
        self.imageAttachments = try container.decodeIfPresent([ChatImageAttachment].self, forKey: .imageAttachments) ?? []
        self.contentBlocks = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sender, forKey: .sender)
        try container.encode(text, forKey: .text)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(toolCall, forKey: .toolCall)
        try container.encode(imageAttachments, forKey: .imageAttachments)
    }
}

/// AI 对话页面整体状态 — 对齐 Flutter `AiChatModel`。
struct AiChatModel: Equatable {
    var petEmoji: String = "🐱"
    var petNameKey: String = "petNameHuahua"
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading: Bool = false

    /// 用户在输入框中选中的文件/目录引用列表。
    var selectedReferences: [ReferenceItem] = []

    /// 用户在输入框中附加的图片列表（待发送）。
    var pendingImageAttachments: [ChatImageAttachment] = []

    /// 将选中的引用拼接为发送给 Hermes 的文本片段（使用绝对路径）。
    var referenceText: String {
        selectedReferences.map { $0.path }.joined(separator: " ")
    }

    /// 当前输入是否为空（文本、引用、图片都没有）。
    var isInputEmpty: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && selectedReferences.isEmpty
        && pendingImageAttachments.isEmpty
    }

    /// 当前会话 ID（来自 Hermes 后端）。
    var sessionId: String?

    /// SSE 流式响应的实时文本片段。
    var streamingContent: String?

    /// 流式回复的 UI 内容块（实时构建）。
    var streamingBlocks: [ContentBlock] = []

    /// 当前流中的工具调用进度列表（Hermes `hermes.tool.progress`）。
    var toolProgressEvents: [ToolProgressEvent] = []

    /// 当前 SSE 连接状态。
    var connectionState: ChatConnectionState = .idle

    /// 错误信息（仅在 connectionState == .error 时显示）。
    var errorMessage: String?

    /// 当前会话标题（由后端或用户设置）。
    var sessionTitle: String?

    /// 会话侧边栏是否可见。
    var sidebarVisible: Bool = true

    /// 当前默认模型信息（从 `~/.hermes/config.yaml` 读取）。
    /// 仅用于 UI 展示 — 实际请求体仍由后端 `config.yaml` 决定。
    var currentModel: CurrentModelInfo?

    /// 当前推理强度（覆盖 `~/.hermes/config.yaml` 中 `agent.reasoning_effort`）。
    ///
    /// 官方文档：
    /// [reasoning_effort](https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/configuration#%E6%8E%A8%E7%90%86%E5%8A%AA%E5%8A%9B%E7%A8%8B%E5%BA%A6)
    /// 字段 — `none | low | minimal | medium | high | xhigh`。
    ///
    /// - 本字段为**请求级覆盖**：每次 `sendMessage` 时随请求体一同下发。
    /// - 默认 `.medium` 与官方默认值一致。
    /// - 用户在下拉菜单中切换 → 同步写入 `config.yaml` → 持久化。
    var reasoningEffort: ReasoningEffort = .medium

    /// 当前工作区目录（对应 `~/.hermes/config.yaml` 中 `terminal.cwd`）。
    ///
    /// 设置后 Hermes `terminal` 工具会在此目录下执行命令，避免 AI 在其他区域操作。
    /// `nil` 表示使用 Hermes 默认行为。
    var workingDirectory: String? = nil

    /// 助手是否正在生成回复。
    var isStreaming: Bool {
        connectionState == .streaming || connectionState == .connecting
    }

    // MARK: - Voice input

    /// 是否正在通过麦克风进行本地语音识别。
    var isRecording: Bool = false

    /// 语音转写的实时文本；录音时同步写入输入框，结束后清空。
    var voiceTranscribedText: String = ""

    /// 语音识别错误提示。
    var voiceError: String? = nil
}
