import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 聊天输入栏 — 整体黑白风格设计。
///
/// 设计要点：
/// 1. **富文本大输入框** — `NSTextView` 包装，支持多行、粘贴富文本、撤销/重做、
///    选中文本样式（粗体/斜体/代码块/链接 — `NSAttributedString` 形式存储）。
///    行高自适应（`1...12` 行），超过 12 行后开始内部滚动。
/// 2. **推理强度选项** — 顶部 chip + Menu 下拉，6 档：
///    `none | minimal | low | medium | high | xhigh`（对齐 Hermes 官方文档）。
/// 3. **底部工具栏** — 左侧字符计数 / 提示，右侧附件 + 发送按钮。
struct InputBar: View {
    @Binding var text: String
    @Binding var selectedReferences: [ReferenceItem]
    @Binding var pendingImageAttachments: [ChatImageAttachment]
    let isStreaming: Bool
    let petNameKey: String
    let isDark: Bool
    let reasoningEffort: ReasoningEffort
    let workingDirectory: String?
    let currentProfile: String?
    let isRecording: Bool
    let voiceError: String?
    let onSend: () -> Void
    let onInputChange: (String) -> Void
    let onReasoningEffortChange: (ReasoningEffort) -> Void
    let onWorkingDirectoryChange: (String?) -> Void
    let onStop: () -> Void
    let onRemoveReference: (String) -> Void
    let onToggleVoiceRecording: () -> Void
    let onAddImageAttachment: (ChatImageAttachment) -> Void
    let onRemoveImageAttachment: (String) -> Void
    /// 是否显示工作区文件选择弹窗（由父视图 AiChatPage 控制）。
    @Binding var showFilePicker: Bool

    /// 焦点状态 — 失焦后自动隐藏 toolbar 描边高亮。
    @FocusState private var isFocused: Bool

    /// 用户通过拖拽手动设置的内容区高度；nil 时按内容自动伸缩。
    @State private var manualHeight: CGFloat?
    /// 拖拽开始时的内容区高度。
    @State private var dragStartHeight: CGFloat?
    /// 当前由内容计算出的内容区高度（不含 padding），用于拖拽起点。
    @State private var computedHeight: CGFloat = 0

    /// TextEditor 自身高度（与 lineLimit 配合，限制最大行数）。
    private static let minLines: Int = 3
    private static let maxLines: Int = 12
    private static let lineHeight: CGFloat = 22

    private var minContentHeight: CGFloat { Self.lineHeight * CGFloat(Self.minLines) }
    private var maxContentHeight: CGFloat { Self.lineHeight * CGFloat(Self.maxLines) }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：推理强度条
            topBar
            // 引用文件/目录 chips
            if !selectedReferences.isEmpty {
                referenceChipsArea
            }
            // 图片附件 chips
            if !pendingImageAttachments.isEmpty {
                imageAttachmentsArea
            }
            // 语音错误提示
            if let voiceError = voiceError, !voiceError.isEmpty {
                voiceErrorBanner(voiceError)
            }
            // 中部：富文本输入框
            inputArea
            // 拖拽调整手柄
            dragHandle
            // 底部：工具栏
            bottomBar
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Palette.bgPanel)
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Top bar (reasoning effort)

    /// 顶部条：左 标签"推理强度"，右 Menu 切换。
    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Palette.textTertiary)
                Text("推理强度")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.3)
                    .foregroundColor(Palette.textTertiary)
            }

            reasoningEffortMenu

            Spacer()

            // 简短副标题 — 帮助用户理解当前档位
            Text(reasoningEffort.subtitle)
                .font(.system(size: 11))
                .foregroundColor(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.bottom, 8)
    }

    /// 推理强度下拉菜单 — 6 档可选项。
    private var reasoningEffortMenu: some View {
        Menu {
            ForEach(ReasoningEffort.allCases) { effort in
                Button {
                    onReasoningEffortChange(effort)
                } label: {
                    HStack(spacing: 8) {
                        // 当前选中打勾（与 NSPopUpMenu 一致）；
                        // 未选中占位固定宽度，保持菜单项左对齐。
                        Group {
                            if effort == reasoningEffort {
                                Image(systemName: "checkmark")
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(effort.displayName)
                                .font(.system(size: 12, weight: .medium))
                            Text(effort.subtitle)
                                .font(.system(size: 10))
                                .opacity(0.7)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(reasoningEffort.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Palette.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Palette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Palette.border, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Voice error banner

    private func voiceErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundColor(Palette.textPrimary)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(2)
            Spacer()
            if message.contains("听写") || message.contains("键盘") {
                Button(action: openDictationSettings) {
                    Text("打开设置")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Palette.inverseInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Palette.inverse)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.bgBase)
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func openDictationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Reference chips

    /// 选中的文件/目录 chip 列表。
    private var referenceChipsArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selectedReferences) { ref in
                    referenceChip(ref)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 10)
        .background(Palette.bgBase)
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    /// 单个引用 chip — 目录显示文件夹图标 + 名称，文件显示文件图标 + 名称。
    private func referenceChip(_ ref: ReferenceItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ref.isDirectory ? "folder.fill" : "doc.text.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(ref.isDirectory ? Color.blue.opacity(0.8) : Palette.textSecond)
            Text(ref.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(action: { onRemoveReference(ref.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Palette.border, lineWidth: 1)
                )
        )
        .help(ref.path)
    }

    // MARK: - Image attachment chips

    /// 待发送图片附件预览区 — 显示在输入框上方，用户可继续输入文字后一起发送。
    private var imageAttachmentsArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImageAttachments) { attachment in
                    imageAttachmentChip(attachment)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 10)
        .background(Palette.bgBase)
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    /// 单个图片附件 chip — 左侧缩略图、右侧文件名 + 删除按钮。
    private func imageAttachmentChip(_ attachment: ChatImageAttachment) -> some View {
        HStack(spacing: 8) {
            if let image = NSImage.fromDataUrl(attachment.dataUrl) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(Palette.textSecond)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("\(imagePixelDescription(for: attachment)) · 已附加")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 90, alignment: .leading)

            Button(action: { onRemoveImageAttachment(attachment.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Palette.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(Palette.bgPanel)
                            .overlay(Circle().stroke(Palette.border, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Palette.border, lineWidth: 1)
                )
        )
        .help(attachment.localPath ?? attachment.displayName)
    }

    /// 从 data URL 解析出图片尺寸描述，用于 chip 副标题。
    private func imagePixelDescription(for attachment: ChatImageAttachment) -> String {
        guard let image = NSImage.fromDataUrl(attachment.dataUrl) else { return "未知尺寸" }
        return "\(Int(image.size.width))×\(Int(image.size.height))"
    }

    // MARK: - Input area (rich text)

    /// 富文本输入框 — 基于 `NSTextView` 的 SwiftUI 包装。
    ///
    /// 交互设计：
    /// - **占位提示** 在输入框左上角，与首行文字位置对齐。
    /// - **整个圆角矩形区域** 都是点击范围：点击空白处会激活 `NSTextView`
    ///   并把光标落在合适位置（`placeholder rect` → 首行 / 最近一次点击位置）。
    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            // 1. 背景填充（圆角矩形）
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.bgBase)

            // 2. 整框点击区 — 覆盖整个圆角矩形，
            //    点在 NSTextView 之外（四周 padding）也能聚焦。
            //    使用 `contentShape(Rectangle())` 让透明区域也可命中。
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = true
                }

            // 3. 占位提示 — 顶部左对齐（与 NSTextView 文字起点对齐：
            //    10pt SwiftUI padding + 4pt textContainerInset = 14，
            //    6pt SwiftUI padding + 6pt textContainerInset = 12）。
            if text.isEmpty {
                Text(isRecording ? "正在听您说话…" : hintText)
                    .font(.system(size: 14))
                    .foregroundColor(isRecording ? Palette.recording : Palette.textTertiary)
                    .padding(.leading, 14)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }

            // 4. 富文本编辑 — NSTextView 自身处理自己的点击事件。
            RichTextEditor(
                text: $text,
                isFocused: $isFocused,
                isEditable: !isRecording,
                onChange: onInputChange,
                onSubmit: send,
                minHeight: minContentHeight,
                maxHeight: maxContentHeight,
                fixedHeight: manualHeight,
                onHeightChange: { height in
                    computedHeight = height
                },
                workingDirectory: workingDirectory,
                isFilePickerPresented: $showFilePicker,
                onFilePickerTrigger: { showFilePicker = true },
                onPasteImage: { onAddImageAttachment($0) }
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(
            minHeight: (manualHeight ?? minContentHeight) + 16,
            maxHeight: (manualHeight ?? maxContentHeight) + 16
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? Palette.textSecond : Palette.border,
                    lineWidth: isFocused ? 1.2 : 1
                )
        )
    }

    // MARK: - Drag handle

    /// 输入框底部拖拽手柄 — 上下拖动可调整输入框高度，双击恢复自动高度。
    @State private var isHandleHovered = false
    @State private var isDraggingHandle = false
    @State private var resizeCursorPushed = false

    private var dragHandle: some View {
        Rectangle()
            .fill(Palette.textTertiary.opacity(0.5))
            .frame(width: 36, height: 4)
            .cornerRadius(2)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHandleHovered = hovering
                updateResizeCursor()
            }
            .onTapGesture(count: 2) {
                manualHeight = nil
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if !isDraggingHandle {
                            isDraggingHandle = true
                            updateResizeCursor()
                        }
                        if dragStartHeight == nil {
                            dragStartHeight = manualHeight ?? computedHeight
                        }
                        let newHeight = dragStartHeight! - value.translation.height
                        manualHeight = max(minContentHeight, min(maxContentHeight, newHeight))
                    }
                    .onEnded { _ in
                        dragStartHeight = nil
                        isDraggingHandle = false
                        updateResizeCursor()
                    }
            )
    }

    private func updateResizeCursor() {
        let needsResize = isHandleHovered || isDraggingHandle
        if needsResize && !resizeCursorPushed {
            NSCursor.resizeUpDown.push()
            resizeCursorPushed = true
        } else if !needsResize && resizeCursorPushed {
            NSCursor.pop()
            resizeCursorPushed = false
        }
    }

    // MARK: - Bottom bar (tools + send)

    private var bottomBar: some View {
        HStack(spacing: 10) {
            // 工作区目录选择器
            workingDirectoryButton

            // 字符计数（小号、不抢眼）
            Text("\(text.count) 字")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Palette.textTertiary)

            Spacer()

            // 语音输入按钮
            voiceButton

            // 图片按钮：展开菜单选择截图或本地图片
            imageAttachmentMenu

            // 发送按钮
            sendButton
        }
        .padding(.top, 10)
    }

    /// 工作区目录选择按钮。
    private var workingDirectoryButton: some View {
        let hasCwd = workingDirectory?.isEmpty == false
        return ZStack(alignment: .topTrailing) {
            HStack(spacing: 6) {
                Image(systemName: workingDirectoryIcon)
                    .font(.system(size: 10, weight: .medium))
                Text(workingDirectoryDisplay)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundColor(Palette.textSecond)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Palette.border, lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture { selectWorkingDirectory() }

            if hasCwd {
                Button(action: { onWorkingDirectoryChange(nil) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Palette.textTertiary)
                        .frame(width: 14, height: 14)
                        .background(
                            Circle()
                                .fill(Palette.bgPanel)
                                .overlay(
                                    Circle()
                                        .stroke(Palette.border, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding([.top, .trailing], 2)
                .help("清除工作区")
            }
        }
        .contextMenu {
            if hasCwd {
                Button("清除工作区") {
                    onWorkingDirectoryChange(nil)
                }
            }
        }
        .help(workingDirectoryHelp)
    }

    private var workingDirectoryIcon: String {
        (workingDirectory?.isEmpty == false) ? "folder.fill" : "folder"
    }

    private var workingDirectoryDisplay: String {
        guard let dir = workingDirectory, !dir.isEmpty else { return "选择工作区" }
        return (dir as NSString).lastPathComponent
    }

    private var workingDirectoryHelp: String {
        let profileSuffix = currentProfile.map { " [profile: \($0)]" } ?? " [profile: default]"
        guard let dir = workingDirectory, !dir.isEmpty else {
            return "点击选择 AI 工作目录" + profileSuffix
        }
        return "当前工作区：\(dir)" + profileSuffix
    }

    private func selectWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            onWorkingDirectoryChange(url.path)
        }
    }

    private var sendButton: some View {
        Button(action: isStreaming ? stop : send) {
            Group {
                if isStreaming {
                    HStack(spacing: 5) {
                        Image(systemName: "square.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("停止")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Palette.textPrimary)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                        Text("发送")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Palette.inverseInk)
                }
            }
            .frame(minWidth: 60, minHeight: 32)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isStreaming ? Palette.bgElevated : Palette.inverse)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Palette.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isStreaming && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedReferences.isEmpty && pendingImageAttachments.isEmpty)
        .opacity((!isStreaming && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedReferences.isEmpty && pendingImageAttachments.isEmpty) ? 0.4 : 1.0)
    }

    private var voiceButton: some View {
        Button(action: onToggleVoiceRecording) {
            Image(systemName: isRecording ? "stop.fill" : "mic")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isRecording ? Palette.inverseInk : Palette.textSecond)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRecording ? Palette.recording : Palette.bgPanel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Palette.border, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isStreaming)
        .opacity(isStreaming ? 0.4 : 1.0)
        .help(isRecording ? "点击结束录音" : "点击开始语音输入")
    }

    /// 图片附件菜单按钮 — 点击展开“截图”与“选择本地图片”选项。
    private var imageAttachmentMenu: some View {
        Menu {
            Button {
                takeScreenshot()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                    Text("截图")
                }
            }

            Button {
                selectLocalImage()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("选择本地图片")
                }
            }
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Palette.textSecond)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Palette.bgPanel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Palette.border, lineWidth: 1)
                        )
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(isStreaming)
        .opacity(isStreaming ? 0.4 : 1.0)
    }

    // MARK: - Actions

    private func send() {
        guard !isStreaming else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || !selectedReferences.isEmpty
              || !pendingImageAttachments.isEmpty else { return }
        onSend()
    }

    /// 调用系统截图工具捕获区域截图。
    private func takeScreenshot() {
        ImageAttachmentManager.shared.captureScreenshot { result in
            switch result {
            case .success(let attachment):
                self.onAddImageAttachment(attachment)
            case .failure(let error):
                // 用户主动取消不弹提示。
                if let err = error as? ImageAttachmentError, err == ImageAttachmentError.cancelled {
                    return
                }
                DMLogger.log("Screenshot failed: \(error.localizedDescription)", name: "InputBar")
            }
        }
    }

    /// 弹出 NSOpenPanel 选择本地图片文件。
    private func selectLocalImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "选择"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .image]

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            ImageAttachmentManager.shared.attachImage(from: url) { result in
                switch result {
                case .success(let attachment):
                    self.onAddImageAttachment(attachment)
                case .failure(let error):
                    DMLogger.log("Attach image failed: \(error.localizedDescription)", name: "InputBar")
                }
            }
        }
    }

    private func stop() {
        guard isStreaming else { return }
        onStop()
    }

    private var hintText: String {
        return "请发送工作内容"
    }
}

// MARK: - Rich text editor (NSTextView wrapper)

/// 基于 `NSTextView` 的 SwiftUI 富文本输入组件。
///
/// - 支持 `NSAttributedString`（粗体/斜体/代码块/链接/列表 — `⌘B/⌘I/⌘K/⌘L`）。
/// - 多行、撤销/重做（系统默认）。
/// - 行高自适应；超过 `maxLines` 行后启用内部滚动。
/// - 失焦后保留内容；`onSubmit` 回调在用户按 ⌘↩ 时触发。
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var isEditable: Bool = true
    let onChange: (String) -> Void
    let onSubmit: () -> Void
    let minHeight: CGFloat
    let maxHeight: CGFloat
    var fixedHeight: CGFloat? = nil
    var onHeightChange: ((CGFloat) -> Void)? = nil
    /// 当前工作区目录；仅当非空时输入 `#` 才会触发文件选择弹窗。
    var workingDirectory: String? = nil
    /// 弹窗是否已显示，避免连续触发。
    var isFilePickerPresented: Binding<Bool>? = nil
    /// 检测到 `#` 且满足条件时的回调。
    var onFilePickerTrigger: (() -> Void)? = nil
    /// 从剪贴板粘贴图片时的回调。
    var onPasteImage: ((ChatImageAttachment) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        context.coordinator.configure(textView: textView)
        // 高度约束在 updateNSView 中更新
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // 同步可编辑状态（语音输入时禁用键盘输入）
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }

        let oldString = textView.string
        let textChanged = oldString != text

        // 文本外部更新时回写到 NSTextView
        if textChanged {
            // 保留 attributed 内容（仅当外部 text 是内部 attributed 的纯文本投影时）
            let attr = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.white
                ]
            )
            textView.textStorage?.setAttributedString(attr)
            // 同步触发器检测用的文本记录，避免弹窗关闭后外部插入路径导致误判。
            context.coordinator.lastCheckedText = text
        }

        // 同步焦点：当 SwiftUI @FocusState 变为 true 时，把 NSTextView 提升为第一响应者。
        if isFocused.wrappedValue, let win = textView.window,
           win.firstResponder !== textView {
            DispatchQueue.main.async {
                win.makeFirstResponder(textView)
            }
        }

        // 高度约束（外部重置文本时平滑过渡，避免发送后输入框突然塌陷导致页面抖动）
        let animate = textChanged && abs(oldString.count - text.count) > 10
        context.coordinator.updateHeight(
            scrollView: nsView,
            maxHeight: maxHeight,
            fixedHeight: fixedHeight,
            animated: animate
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: RichTextEditor
        private var heightConstraint: NSLayoutConstraint?
        /// 上次检测触发器时的文本，用于判断用户是否刚输入 `#`。
        var lastCheckedText: String = ""

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func configure(textView: NSTextView) {
            textView.delegate = self
            textView.isEditable = parent.isEditable
            textView.isSelectable = true
            textView.isRichText = true
            textView.allowsUndo = true
            textView.usesFontPanel = true
            textView.usesRuler = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = true
            textView.isGrammarCheckingEnabled = false
            textView.smartInsertDeleteEnabled = false
            textView.drawsBackground = false
            textView.backgroundColor = .clear
            textView.textContainerInset = NSSize(width: 4, height: 6)
            textView.font = NSFont.systemFont(ofSize: 14)
            textView.textColor = .white
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            // 初始 attributed 字符串
            if !parent.text.isEmpty {
                textView.textStorage?.setAttributedString(
                    NSAttributedString(
                        string: parent.text,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 14),
                            .foregroundColor: NSColor.white
                        ]
                    )
                )
            }
        }

        func updateHeight(
            scrollView: NSScrollView,
            maxHeight: CGFloat,
            fixedHeight: CGFloat? = nil,
            animated: Bool = false
        ) {
            guard let textView = scrollView.documentView as? NSTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }

            // 若用户手动拖拽设定了高度，则优先使用该高度；否则按内容自动计算。
            let target: CGFloat
            if let fixedHeight = fixedHeight {
                target = fixedHeight
            } else {
                // 计算文本高度（当前 SDK 的 `usedRect(for:)` 返回可选 CGRect）。
                layoutManager.ensureLayout(for: textContainer)
                let textHeight = layoutManager.usedRect(for: textContainer).height
                let inset = textView.textContainerInset.height * 2
                target = min(maxHeight, max(parent.minHeight, textHeight + inset))
            }

            // 回传当前实际内容区高度，供拖拽起点使用。
            parent.onHeightChange?(target)

            if heightConstraint == nil {
                let c = scrollView.heightAnchor.constraint(equalToConstant: target)
                c.priority = NSLayoutConstraint.Priority.defaultHigh
                c.isActive = true
                heightConstraint = c
            } else {
                guard heightConstraint?.constant != target else { return }
                if animated {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.15
                        context.allowsImplicitAnimation = true
                        heightConstraint?.animator().constant = target
                    }
                } else {
                    heightConstraint?.constant = target
                }
            }
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newValue = textView.string
            // 使用 DispatchQueue.main.async 避免在 SwiftUI update 流程中触发 binding 循环
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.parent.text = newValue
                self.parent.onChange(newValue)
                self.checkFilePickerTrigger(textView: textView)
                if let scrollView = textView.enclosingScrollView {
                    self.updateHeight(
                        scrollView: scrollView,
                        maxHeight: self.parent.maxHeight,
                        fixedHeight: self.parent.fixedHeight
                    )
                }
            }
        }

        /// 检测用户是否刚输入 `#` 且工作区已设置；若是则触发文件选择弹窗。
        private func checkFilePickerTrigger(textView: NSTextView) {
            guard let cwd = self.parent.workingDirectory, !cwd.isEmpty else { return }
            guard !(self.parent.isFilePickerPresented?.wrappedValue ?? true) else { return }
            guard self.parent.onFilePickerTrigger != nil else { return }

            let value = textView.string
            // 仅在本次输入使文本尾部出现 `#` 时触发一次。
            // 这样可以避免弹窗关闭后重复触发，也允许用户删除 `#` 后重新输入来再次触发。
            let didJustAppendHash = !self.lastCheckedText.hasSuffix("#") && value.hasSuffix("#")
            self.lastCheckedText = value
            guard didJustAppendHash else { return }

            self.parent.isFilePickerPresented?.wrappedValue = true
            self.parent.onFilePickerTrigger?()
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy selector: Selector
        ) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                let mods = event?.modifierFlags ?? []
                // ⇧↩ 换行，↩ / ⌘↩ 发送
                if mods.contains(.shift) {
                    return false
                }
                parent.onSubmit()
                return true
            }

            if selector == #selector(NSText.paste(_:)) {
                return handlePasteImage()
            }

            return false
        }

        /// 拦截 Cmd+V；剪贴板里有图片时转成附件并阻止默认文本粘贴，否则保持原行为。
        private func handlePasteImage() -> Bool {
            let pasteboard = NSPasteboard.general
            guard parent.onPasteImage != nil else { return false }

            // 1. 优先读取剪贴板中的图片对象（截图、浏览器复制图片等）。
            if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
               let image = images.first {
                ImageAttachmentManager.shared.attachImage(from: image, displayName: "pasted_image") { result in
                    switch result {
                    case .success(let attachment):
                        self.parent.onPasteImage?(attachment)
                    case .failure(let error):
                        DMLogger.log("Paste image failed: \(error.localizedDescription)", name: "InputBar")
                    }
                }
                return true
            }

            // 2. 兼容剪贴板中的文件 URL（如 macOS 截图临时路径、file:// 图片 URI）。
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               let url = urls.first,
               url.isFileURL,
               isImageFile(url) {
                ImageAttachmentManager.shared.attachImage(from: url) { result in
                    switch result {
                    case .success(let attachment):
                        self.parent.onPasteImage?(attachment)
                    case .failure(let error):
                        DMLogger.log("Paste image file failed: \(error.localizedDescription)", name: "InputBar")
                    }
                }
                return true
            }

            return false
        }

        private func isImageFile(_ url: URL) -> Bool {
            let imageTypes: [UTType] = [.png, .jpeg, .tiff, .gif, .image]
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return imageTypes.contains { type.conforms(to: $0) }
        }
    }
}

// MARK: - Palette

private enum Palette {
    static let bgBase      = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let bgElevated  = Color(red: 0.078, green: 0.078, blue: 0.078)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
    static let inverse     = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let inverseInk  = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let recording   = Color(red: 0.920, green: 0.250, blue: 0.250)
}

// MARK: - NSImage helpers

extension NSImage {
    /// 从 `data:image/...;base64,...` 字符串解析为 NSImage。
    static func fromDataUrl(_ dataUrl: String) -> NSImage? {
        guard let commaIndex = dataUrl.firstIndex(of: ",") else { return nil }
        let base64 = String(dataUrl[dataUrl.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}
