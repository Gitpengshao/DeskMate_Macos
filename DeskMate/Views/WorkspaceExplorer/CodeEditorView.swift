import SwiftUI
import AppKit

// 当 CodeEditSourceEditor SPM 依赖可用时导入
#if canImport(CodeEditSourceEditor)
import CodeEditSourceEditor
import CodeEditLanguages
#endif

/// 代码编辑器视图 — 基于 CodeEditSourceEditor 的 SwiftUI 包装。
///
/// 当 SPM 依赖 `CodeEditSourceEditor` 解析成功后自动启用语法高亮，
/// 否则降级为基于 NSTextView 的纯文本编辑器。
struct CodeEditorView: View {
    let fileURL: URL
    @Binding var content: String
    @Binding var isDirty: Bool
    var baselineContent: String = ""
    var onViewDiff: (() -> Void)?
    var onSave: ((String) -> Void)?

    @State private var statusMessage: String?
    @State private var diffGutterCoordinator = DiffGutterCoordinator()

    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息栏
            editorHeader

            Divider().background(Palette.border)

            // 编辑器主体
            codeEditView

            // 底部状态栏
            editorStatusBar
        }
        .background(Palette.bgBase)
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundColor(Palette.textSecond)

            Text(fileURL.lastPathComponent)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            if isDirty {
                Text("● 未保存")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.accent)
            }

            Spacer()

            // 查看 Diff 入口
            if let onViewDiff = onViewDiff {
                Button(action: onViewDiff) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right.circle")
                            .font(.system(size: 10))
                        Text("Diff")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Palette.textSecond)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Palette.bgElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Palette.border, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("查看 Diff")
            }

            // 文件路径提示
            Text(fileURL.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(fileURL.path)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.bgPanel)
    }

    // MARK: - Code Editor

    @ViewBuilder
    private var codeEditView: some View {
#if canImport(CodeEditSourceEditor)
        codeEditSourceEditorView
#else
        fallbackTextView
#endif
    }

    // MARK: - CodeEditSourceEditor (when available)

#if canImport(CodeEditSourceEditor)
    private var editorTheme: EditorTheme {
        EditorTheme(
            text: .init(color: NSColor.white),
            insertionPoint: NSColor.white,
            invisibles: .init(color: NSColor(white: 0.4, alpha: 0.5)),
            background: NSColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 1.0),
            lineHighlight: NSColor(white: 0.08, alpha: 1.0),
            selection: NSColor(white: 0.3, alpha: 0.5),
            keywords: .init(color: NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)),
            commands: .init(color: NSColor(red: 0.8, green: 0.4, blue: 0.8, alpha: 1.0)),
            types: .init(color: NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)),
            attributes: .init(color: NSColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0)),
            variables: .init(color: NSColor(red: 0.6, green: 0.6, blue: 1.0, alpha: 1.0)),
            values: .init(color: NSColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1.0)),
            numbers: .init(color: NSColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1.0)),
            strings: .init(color: NSColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)),
            characters: .init(color: NSColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)),
            comments: .init(color: NSColor(white: 0.5, alpha: 1.0))
        )
    }

    @State private var editorState = SourceEditorState()

    private var codeEditSourceEditorView: some View {
        SourceEditor(
            $content,
            language: detectedLanguage,
            configuration: SourceEditorConfiguration(
                appearance: SourceEditorConfiguration.Appearance(
                    theme: editorTheme,
                    useThemeBackground: true,
                    font: font,
                    lineHeightMultiple: 1.3,
                    wrapLines: false,
                    tabWidth: 4
                )
            ),
            state: $editorState,
            coordinators: [diffGutterCoordinator]
        )
        .onChange(of: content) { _, newValue in
            isDirty = true
            DMLogger.log("CodeEditorView content changed: length=\(newValue.count), dirty=\(isDirty)", name: "DiffDebug")
        }
        .onChange(of: baselineContent) { _, newValue in
            DMLogger.log("CodeEditorView baselineContent changed: length=\(newValue.count)", name: "DiffDebug")
            diffGutterCoordinator.setBaseContent(newValue)
        }
        .onAppear {
            DMLogger.log("CodeEditorView appear: baselineLength=\(baselineContent.count)", name: "DiffDebug")
            diffGutterCoordinator.setBaseContent(baselineContent)
        }
        .contentShape(Rectangle())
        .clipped()
    }

    private var detectedLanguage: CodeLanguage {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "swift":   return .swift
        case "py":      return .python
        case "js", "cjs", "mjs": return .javascript
        case "ts", "cts", "mts": return .typescript
        case "jsx":     return .jsx
        case "tsx":     return .tsx
        case "kt", "kts": return .kotlin
        case "java", "jav": return .java
        case "go":      return .go
        case "rs":      return .rust
        case "c":       return .c
        case "cpp", "cc", "cxx": return .cpp
        case "h":       return .cpp
        case "hpp":     return .cpp
        case "m":       return .objc
        case "mm":      return .objc
        case "rb":      return .ruby
        case "php":     return .php
        case "sh", "bash": return .bash
        case "yaml", "yml": return .yaml
        case "json":    return .json
        case "xml", "plist": return .html
        case "md":      return .markdown
        case "html", "htm", "shtml": return .html
        case "css":     return .css
        case "sql":     return .sql
        case "toml":    return .toml
        case "lua":     return .lua
        case "dart":    return .dart
        default:        return .default
        }
    }
#endif

    // MARK: - Fallback (NSTextView)

    private var fallbackTextView: some View {
        SimpleCodeEditor(
            text: $content,
            font: font,
            isDirty: $isDirty,
            baselineContent: baselineContent
        )
        .contentShape(Rectangle())
        .clipped()
    }

    // MARK: - Status bar

    private var editorStatusBar: some View {
        HStack(spacing: 12) {
            // 行数 / 字符数
            Text("\(content.components(separatedBy: .newlines).count) 行")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Palette.textTertiary)

            Text("\(content.count) 字符")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Palette.textTertiary)

            Spacer()

            if let msg = statusMessage {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(Palette.textSecond)
            }

            // 保存按钮
            Button(action: saveFile) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10))
                    Text("保存")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isDirty ? Palette.textPrimary : Palette.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isDirty ? Palette.bgElevated : Palette.bgPanel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Palette.border, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!isDirty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Palette.bgPanel)
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Actions

    private func saveFile() {
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            isDirty = false
            onSave?(content)
            statusMessage = "已保存"
            // 2 秒后清除状态消息
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if self.statusMessage == "已保存" {
                    self.statusMessage = nil
                }
            }
        } catch {
            statusMessage = "保存失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - SimpleCodeEditor (Fallback)

/// 降级方案：基于 NSTextView 的简洁代码编辑器。
private struct SimpleCodeEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    @Binding var isDirty: Bool
    let baselineContent: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.font = font
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let markerView = EditorDiffGutterView(frame: NSRect(x: 0, y: 0, width: 3, height: textView.bounds.height))
        markerView.textView = textView
        markerView.autoresizingMask = [.height]
        textView.addSubview(markerView)
        context.coordinator.markerView = markerView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        let newText = text
        if textView.string != newText {
            let selectedRange = textView.selectedRange
            textView.string = newText
            textView.setSelectedRange(selectedRange)
        }

        context.coordinator.updateMarkers(baseline: baselineContent, current: text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: SimpleCodeEditor
        var markerView: EditorDiffGutterView?

        init(_ parent: SimpleCodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.isDirty = true
            updateMarkers(baseline: parent.baselineContent, current: textView.string)
        }

        func updateMarkers(baseline: String, current: String) {
            let markers = TextDiffer.lineMarkers(old: baseline, new: current)
            markerView?.update(markers: markers)
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
    static let accent      = Color(red: 0.200, green: 0.600, blue: 1.000)
}