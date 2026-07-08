import SwiftUI
import MarkdownUI

/// 宠物消息气泡（左对齐）— 整体黑白风格设计。
/// AI 回复使用 MarkdownUI 渲染，支持代码块复制与工具进度展示。
struct PetMessageBubble: View {
    let message: ChatMessage
    let petEmoji: String
    let petNameKey: String
    let isDark: Bool
    let isStreaming: Bool
    let toolProgressEvents: [ToolProgressEvent]

    var body: some View {
        if isStreaming && message.text.isEmpty {
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
            Text(petEmoji)
                .font(.system(size: 16))
        }
        .frame(width: 36, height: 36)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !toolProgressEvents.isEmpty {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Palette.textSecond)
                        .lineLimit(10)
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
