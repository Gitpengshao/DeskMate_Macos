import SwiftUI
import MarkdownUI

/// 宠物消息气泡（左对齐）— 整体黑白风格设计。
/// AI 回复拆分为多个 ContentBlock，支持 thought/action/observation/文件改动。
struct PetMessageBubble: View {
    let message: ChatMessage
    let petEmoji: String
    let petNameKey: String
    let isDark: Bool
    let isStreaming: Bool
    let toolProgressEvents: [ToolProgressEvent]

    private var hasContentBlocks: Bool {
        !message.contentBlocks.isEmpty
    }

    var body: some View {
        if isStreaming && message.text.isEmpty && !hasContentBlocks {
            // 等待阶段：整 item 用 think 精灵图帧动画，无头像 / 文字。
            HStack {
                SpriteFrameAnimationView(
                    config: PetAnimation.think.config,
                    fps: 18,
                    displaySize: 90
                )
                Spacer()
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    bubble
                    if !isStreaming {
                        Text(message.timestamp)
                            .font(.system(size: 10))
                            .foregroundColor(Palette.textTertiary)
                    }
                }
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Palette.bgPanel)
                .overlay(Circle().stroke(Palette.border, lineWidth: 1))
            Image("applogo")
                .resizable()
                .scaledToFit()
                .padding(6)
        }
        .frame(width: 36, height: 36)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isStreaming && !toolProgressEvents.isEmpty {
                streamingProgressPanel
            }

            if hasContentBlocks {
                ContentBlocksView(
                    blocks: message.contentBlocks,
                    isStreaming: isStreaming
                )
            } else {
                Markdown(message.text)
                    .markdownTheme(.deskMateDark)
                    .markdownBlockStyle(\.codeBlock) { configuration in
                        configuration.label
                            .padding(10)
                            .background(Palette.bgElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Palette.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                CopyCodeButton(code: configuration.content)
                                    .padding(6)
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let toolCall = message.toolCall, !toolCall.isEmpty {
                    Text(toolCall)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.bgPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Palette.border, lineWidth: 1)
                )
        )
    }

    private var streamingProgressPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                    .tint(Palette.textSecond)
                Text("思考中")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.textSecond)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(toolProgressEvents) { event in
                    ToolProgressChip(event: event)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Palette.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Content blocks

/// 渲染一组 ContentBlock，支持 thought / action / observation / file-change。
private struct ContentBlocksView: View {
    let blocks: [ContentBlock]
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block {
                case .text(let text):
                    TextBlockView(text: text)
                case .reasoning(let text, let isPending):
                    ReasoningBlockView(text: text, isPending: isPending || isStreaming)
                case .toolCall(let toolCall):
                    ToolCallBlockView(toolCall: toolCall)
                case .observation(let observation):
                    ObservationBlockView(observation: observation)
                case .fileChange(let fileChange):
                    FileChangeBlockView(fileChange: fileChange)
                }
            }
        }
    }
}

private struct TextBlockView: View {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(.deskMateDark)
            .markdownBlockStyle(\.codeBlock) { configuration in
                configuration.label
                    .padding(10)
                    .background(Palette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Palette.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        CopyCodeButton(code: configuration.content)
                            .padding(6)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Thought / reasoning 折叠面板。
private struct ReasoningBlockView: View {
    let text: String
    let isPending: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textSecond)
                    Text(isPending ? "思考中…" : "思考过程")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textSecond)
                    Spacer()
                    if isPending {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                            .tint(Palette.textSecond)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Palette.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecond)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Palette.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Action：工具调用展开卡片。
private struct ToolCallBlockView: View {
    let toolCall: ToolCallBlock
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textSecond)
                    Text(toolCall.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Palette.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(toolCall.displayArguments)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Palette.textSecond)
                    .padding(8)
                    .background(Palette.bgPanel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Palette.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Palette.bgPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Observation：工具执行结果展开卡片。
private struct ObservationBlockView: View {
    let observation: ObservationBlock
    @State private var isExpanded = false

    private var statusColor: Color {
        switch observation.status {
        case .completed: return Color.green.opacity(0.8)
        case .failed: return Color.red.opacity(0.8)
        case .running: return Palette.textSecond
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 12))
                        .foregroundColor(statusColor)
                    Text("观察结果: \(observation.toolName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Palette.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(observation.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Palette.textSecond)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Palette.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusIcon: String {
        switch observation.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        }
    }
}

/// 文件改动高亮 chip。
private struct FileChangeBlockView: View {
    let fileChange: FileChangeBlock

    private var displayIcon: String {
        switch fileChange.operation {
        case .add: return "plus.circle.fill"
        case .delete: return "minus.circle.fill"
        case .modify: return "pencil.circle.fill"
        }
    }

    private var displayColor: Color {
        switch fileChange.operation {
        case .add: return Color.green.opacity(0.8)
        case .delete: return Color.red.opacity(0.8)
        case .modify: return Color.yellow.opacity(0.8)
        }
    }

    private var operationText: String {
        switch fileChange.operation {
        case .add: return "新增"
        case .delete: return "删除"
        case .modify: return "修改"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: displayIcon)
                .font(.system(size: 12))
                .foregroundColor(displayColor)
            Text(operationText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textSecond)
            Text(fileChange.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let additions = fileChange.additions, additions > 0 {
                Text("+\(additions)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.green.opacity(0.8))
            }
            if let deletions = fileChange.deletions, deletions > 0 {
                Text("-\(deletions)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.red.opacity(0.8))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(displayColor.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// 用户消息气泡（右对齐，白底黑字）— 整体黑白风格设计。
struct UserMessageBubble: View {
    let message: ChatMessage
    let isDark: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            VStack(alignment: .trailing, spacing: 6) {
                if !message.imageAttachments.isEmpty {
                    imageAttachmentsGrid
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundColor(Palette.inverseInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Palette.inverse)
                        )
                }
            }
            Text(message.timestamp)
                .font(.system(size: 10))
                .foregroundColor(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// 图片附件网格预览（单图大图展示，多图最大 3 列缩略图）。
    private var imageAttachmentsGrid: some View {
        let count = message.imageAttachments.count
        let isSingle = count == 1
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 6),
            count: isSingle ? 1 : min(3, count)
        )
        return LazyVGrid(columns: columns, alignment: .trailing, spacing: 6) {
            ForEach(message.imageAttachments) { attachment in
                if let image = NSImage.fromDataUrl(attachment.dataUrl) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: isSingle ? .fit : .fill)
                        .frame(
                            width: isSingle ? 220 : 80,
                            height: isSingle ? 220 : 80
                        )
                        .clipShape(RoundedRectangle(cornerRadius: isSingle ? 12 : 8))
                        .help(attachment.displayName)
                }
            }
        }
        .frame(maxWidth: isSingle ? .infinity : 260, alignment: .trailing)
    }
}

/// 工具调用消息气泡（居中、低饱和度）— 整体黑白风格设计。
/// tool 角色的消息内容会被解析为 observation + fileChange 块。
struct ToolMessageBubble: View {
    let message: ChatMessage
    let isDark: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 与宠物气泡对齐：头像 36 + 间距 10
            Spacer().frame(width: 46)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wrench")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecond)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    if !message.contentBlocks.isEmpty {
                        ContentBlocksView(blocks: message.contentBlocks, isStreaming: false)
                    } else if !message.text.isEmpty {
                        Text(message.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Palette.textSecond)
                            .lineLimit(10)
                    }
                    Text(message.timestamp)
                        .font(.system(size: 10))
                        .foregroundColor(Palette.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.bgPanel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Palette.border, lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Tool progress

/// Hermes 工具执行进度芯片（running / completed / failed）。
private struct ToolProgressChip: View {
    let event: ToolProgressEvent

    var body: some View {
        HStack(spacing: 6) {
            if event.emoji.isEmpty {
                Image(systemName: statusIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.textSecond)
            } else {
                Text(event.emoji)
                    .font(.system(size: 11))
            }

            Text(displayLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textSecond)
                .lineLimit(1)

            statusIndicator
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Palette.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Palette.border, lineWidth: 1)
        )
        .cornerRadius(6)
        .help("\(event.tool): \(event.label) (\(event.status.rawValue))")
    }

    private var displayLabel: String {
        if event.label.isEmpty { return event.tool }
        return event.label
    }

    private var statusIcon: String {
        switch event.status {
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark"
        case .failed: return "xmark"
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch event.status {
        case .running:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 10, height: 10)
                .tint(Palette.textSecond)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(Palette.textSecond)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(Palette.textSecond)
        }
    }
}

// MARK: - Code copy

/// 代码块右上角复制按钮。
private struct CopyCodeButton: View {
    let code: String
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                Text(copied ? "已复制" : "复制")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(Palette.textSecond)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Palette.bgPanel)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Palette.border, lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("复制代码")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

// MARK: - Markdown theme

private extension Theme {
    /// 匹配 DeskMate 黑白暗黑主题的 Markdown 主题。
    static var deskMateDark: Theme {
        Theme.gitHub
            .text {
                ForegroundColor(.white)
                FontSize(13)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(12)
                ForegroundColor(.white)
            }
    }
}

// MARK: - Palette

private enum Palette {
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let bgElevated  = Color(red: 0.078, green: 0.078, blue: 0.078)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
    static let inverse     = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let inverseInk  = Color(red: 0.000, green: 0.000, blue: 0.000)
}
