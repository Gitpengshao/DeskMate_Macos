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

/// 单条聊天消息 — 对齐 Flutter `ChatMessage`。
struct ChatMessage: Identifiable, Equatable, Codable {
    let id: String
    let sender: MessageSender
    var text: String
    let timestamp: String
    var toolCall: String? // 例如：'🔧 已调用: weather_search(location="Beijing")'
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

    /// 将选中的引用拼接为发送给 Hermes 的文本片段（使用绝对路径）。
    var referenceText: String {
        selectedReferences.map { $0.path }.joined(separator: " ")
    }

    /// 当前会话 ID（来自 Hermes 后端）。
    var sessionId: String?

    /// SSE 流式响应的实时文本片段。
    var streamingContent: String?

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
}
