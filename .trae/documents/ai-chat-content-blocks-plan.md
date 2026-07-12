# AI 聊天详情内容块重构计划

## Context（背景与目标）

当前 DeskMate 的 AI 对话只把 SSE 流当成纯文本处理： assistant 的回复是单个 `text` 字符串，工具调用只显示为进度 chip，工具输出和文件改动都混在正文里，无法区分 thought/action/observation，也无法高亮 AI 对文件的增删改。用户希望参考 hermes-studio 的 Chat 组件，把一次 AI 回复拆成多个类型化的内容块，每类样式不同，并支持工具调用展开/收起、文件改动高亮。

目标：在不替换现有 `/v1/chat/completions` SSE 协议的前提下，把单条 assistant 消息内部拆成 `ContentBlock` 数组，按块渲染；工具调用与文件改动从 SSE 事件和参数中解析，不需要等待后端提供新 API。

## Key decisions（关键决策）

1. **消息组织方式**：单条 `ChatMessage`（`sender == .pet`）内部持有 `[ContentBlock]`，thought/action/observation/file-change 都是同一条 assistant 消息里的块。保持现有 `ChatMessage` 的 `text` 字段作为“原始内容兜底”，用于历史兼容和同步回后端。
2. **数据变更范围**：新增 `ContentBlock` 模型与解析器；`ChatMessage` 增加 `contentBlocks`；`AiChatModel` 增加流式构建中的 `streamingBlocks`；ViewModel 负责在收到 `deltaChunk` / `toolCall` / `toolProgress` 时更新这些块。
3. **UI 变更范围**：重写 `PetMessageBubble` 为按块渲染；新增 `ThoughtBlockView`、`ToolCallBlockView`、`ObservationBlockView`、`FileChangeBlockView`；`AiChatPage` 的 `streamingBubble` 改用 `streamingBlocks`。
4. **文件改动来源**：优先从 `toolCall` 的 `name` 与 `arguments` 推断。覆盖 `write_file`、`create_file`、`apply_diff`、`delete_file`、`shell`（rm/cp/mv/touch）等常见 Hermes 工具，不依赖后端 workspace-run-change API。
5. **Thought 来源**：解析 content 中的 `<think>` / `<thinking>` / `<reasoning>` 标签（参考 hermes-studio 的 `thinking-parser.ts`），并在流式过程中支持未闭合标签的 pending 状态。
6. **Observation 来源**：Hermes 的 `hermes.tool.progress` 事件 status 为 `completed` 或 `failed` 时，生成 observation 块；后续若该工具的输出以 delta 文本形式返回，也合并进同一块。

## Files to modify（关键文件）

- `DeskMate/Models/AiChatModel.swift`
  - 新增 `ContentBlock` enum（text / reasoning / toolCall / observation / fileChange）。
  - `ChatMessage` 增加 `var contentBlocks: [ContentBlock]`。
  - `AiChatModel` 增加 `var streamingBlocks: [ContentBlock] = []`。
- `DeskMate/Services/ChatService.swift`
  - `ToolProgressEvent` 增加 `toolCallId` 与 `output: String?`。
  - `ChatStreamEvent.toolProgress` 在 status 变化时附带已累积的输出文本。
- `DeskMate/Utils/ChatContentParser.swift`（新建）
  - `parseContentBlocks(from:streaming:)`：从 assistant 原始文本提取 reasoning / text / file-change。
  - `detectFileChanges(tool:name:arguments:)`：根据工具名和参数返回 `[FileChangeBlock]`。
  - `protectCodeBlocks` / `restoreCodeBlocks`：防止解析 `<think>` 时误伤代码块里的尖括号。
- `DeskMate/ViewModels/AiChatViewModel.swift`
  - 在 `onStreamEvent` 中收到 `deltaChunk` 时调用解析器，把 `<think>` 内容拆成 reasoning 块，普通文本作为 text 块，同时更新 `model.streamingBlocks`。
  - 收到 `toolCall` 时追加 `.toolCall` 块并附带 `FileChangeBlock`。
  - 收到 `toolProgress(.completed/.failed)` 时追加/更新 `.observation` 块。
  - `onStreamDone` 时把 `streamingBlocks` 写进最终 `ChatMessage.contentBlocks`。
  - `loadSession` 历史消息回填时，也把后端返回的 content 解析成 blocks。
- `DeskMate/Views/AIChat/MessageBubbles.swift`
  - 重写 `PetMessageBubble`：body 遍历 `message.contentBlocks`（为空时回退到 `message.text` 的 Markdown）。
  - 新增 `ReasoningBlockView`：灰底折叠面板，左侧显示“思考过程”+ 字数，支持展开/收起，流式 pending 时显示脉冲动画。
  - 新增 `ToolCallBlockView`：action 块，显示工具名 + 参数 JSON，支持展开/收起，右侧状态图标。
  - 新增 `ObservationBlockView`：observation 块，显示工具输出或状态，默认折叠（内容过长时）。
  - 新增 `FileChangeBlockView`：文件改动行，新增绿色（`+`）、删除红色（`-`）、修改黄色（`~`）高亮，点击可在工作区浏览器打开文件。
- `DeskMate/Views/AIChat/AiChatPage.swift`
  - `streamingBubble` 的构造改为使用 `chatVM.model.streamingBlocks` 而不是纯 `streamingContent`。
  - `messagesArea` 的滚动锚点在流式时继续跟踪 `streaming` id。

## Detailed design（详细设计）

### 1. ContentBlock 模型

```swift
enum ContentBlock: Identifiable, Equatable {
    case text(String)
    case reasoning(text: String, isPending: Bool)
    case toolCall(ToolCallBlock)
    case observation(ObservationBlock)
    case fileChange(FileChangeBlock)

    var id: String { ... }
}

struct ToolCallBlock: Identifiable, Equatable {
    let id: String
    let name: String
    let arguments: [String: Any]
    let displayArguments: String
}

struct ObservationBlock: Identifiable, Equatable {
    let id: String
    let toolName: String
    let text: String
    let status: ToolProgressStatus
}

struct FileChangeBlock: Identifiable, Equatable {
    let id: String
    let path: String
    let operation: FileChangeOperation
}

enum FileChangeOperation { case add, delete, modify }
```

### 2. Thought 解析

移植 hermes-studio 的 `thinking-parser.ts` 到 Swift：
- 先保护 fenced code block 和 inline code 里的内容，避免把代码中的 `<think>` 当标签。
- 匹配 `<think>`, `<thinking>`, `<reasoning>` 到对应闭合标签之间的内容作为 reasoning 段。
- 流式模式下，若存在未闭合标签，把标签后的内容作为 pending reasoning 显示（带“思考中…”动画）。
- 恢复被保护的代码块。

### 3. Action / Observation 解析

- `ChatService.processEvent` 收到 `delta.tool_calls` 时继续生成 `.toolCall` 事件。
- `AiChatViewModel.onStreamEvent(.toolCall)` 时追加 `.toolCall` 块，并调用 `detectFileChanges`：
  - `write_file` / `create_file` / `apply_diff` → 从参数 `path` / `file_path` 取路径，operation 分别为 `.modify` / `.add` / `.modify`。
  - `delete_file` / `delete` → `.delete`。
  - `shell` → 对参数里的命令做简单正则，识别 `rm`, `touch`, `cp`, `mv` 并提取路径。
- `toolProgress(.completed/.failed)` 时：
  - 若已有同 `toolCallId` 的 `.toolCall` 块，在其上追加 `output`。
  - 否则新增 `.observation` 块，文案为 “`tool`: label (status)”。

### 4. 流式构建策略

ViewModel 维护两个状态：
- `model.streamingContent: String?` — 保留，用于兼容旧逻辑和避免解析前闪烁。
- `model.streamingBlocks: [ContentBlock]` — 新增，每次 delta 到达后重新解析整个 buffer。

解析后：
- 若 buffer 里有 reasoning pending，单独把 pending 段更新为 `isPending: true`。
- text 块只保留 body（去掉 think 标签后的内容）。
- toolCall / observation / fileChange 块在流式过程中追加，不参与文本解析。

### 5. UI 样式

保持黑白主色调，不同块用边框/图标/颜色区分：
- **Reasoning**：`bgElevated` 背景，`textSecond` 文字，左侧 `brain.head.profile` 图标，折叠时只显示标题和字数，展开显示完整内容。
- **ToolCall**：`bgPanel` 背景，顶部显示 `wrench` 图标 + 工具名 + 展开箭头，展开后显示等宽 JSON。
- **Observation**：`bgElevated` 背景，顶部显示 `eye` 图标 + “观察结果”，展开显示输出文本/错误。
- **FileChange**：单行 chip， operation 决定左侧图标和颜色：
  - add → `plus.circle.fill` 绿色
  - delete → `minus.circle.fill` 红色
  - modify → `pencil.circle.fill` 黄色
  - 路径过长时 middle truncation。

### 6. 历史消息回填

`loadSession` 把后端返回的 content 字符串同样走 `ChatContentParser.parseContentBlocks(from:streaming:false)`，生成 blocks 存到 `ChatMessage.contentBlocks`。这样重新打开会话后 thought/action 仍可折叠、文件改动仍高亮。

## Implementation order（实施顺序）

1. **模型与解析器**：新增 `ContentBlock` 类型和 `ChatContentParser`，添加单元测试覆盖 `<think>` 解析和代码块保护。
2. **ViewModel 集成**：在 `AiChatViewModel` 的流式事件处理中填充 `streamingBlocks`，并在流结束时写入最终消息；回填历史消息。
3. **气泡 UI**：重写 `PetMessageBubble` 并新增四个 block view；更新 `ToolMessageBubble` 保持与旧 tool sender 兼容。
4. **AiChatPage 适配**：`streamingBubble` 改为从 `streamingBlocks` 渲染；滚动锚点不变。
5. **编译与运行**：`xcodebuild` 构建通过；本地 mock 或真实 Hermes 会话验证 thought/action/observation/file-change 渲染。

## Verification（验证方式）

1. 启动 DeskMate，打开 AI 对话页，发送一条需要推理的消息，确认 `<think>...</think>` 内容被折叠在“思考过程”面板，普通正文正常显示。
2. 发送一条触发工具调用的消息，确认：
   - 工具调用以可展开卡片展示，显示工具名和参数。
   - 工具完成后出现 observation 块，显示结果/状态。
3. 让 AI 修改/新增/删除工作区文件，确认文件改动以对应颜色 chip 高亮，点击可打开工作区浏览器（若已设置工作区）。
4. 切换会话或重启 App 后加载历史消息，确认内容块仍按类型渲染。
5. 构建成功且无新增 SwiftLint / 编译警告。

## Risks（风险与回退）

- **`<think>` 解析误伤代码块**：通过保护代码块机制规避；若仍有问题，可调整正则或关闭 thought 折叠作为回退。
- **文件改动推断不完整**：仅覆盖常见 Hermes 工具名；未来可接入 `/v1/runs/{id}/events` 的 `workspace_run_change` 字段做补充。
- **后端 content 不包含标签**：若 Hermes 不把 reasoning 放在 `<think>` 标签内，则 reasoning 块为空，UI 回退到原有 Markdown 展示，不影响可用性。
- **历史消息格式变化**：`ChatMessage` 新增字段有默认值，Codable 兼容现有缓存。
