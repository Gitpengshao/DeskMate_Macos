import SwiftUI

/// 文件树视图 — 展示目录层级，支持展开/折叠、选中高亮。
///
/// 使用 `ScrollView` + `LazyVStack` 而非 `List`，因为 macOS SwiftUI
/// 的 `List` 会拦截嵌套子视图的 `.contextMenu` 右键事件，导致文件行
/// 的右键菜单无法正常触发。
struct FileTreeView: View {
    let node: FileNode
    let showHidden: Bool
    @Binding var selectedURL: URL?
    let onSelect: (URL) -> Void
    let onOpenDiff: ((URL) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                TreeNodeView(
                    node: node,
                    level: 0,
                    showHidden: showHidden,
                    selectedURL: $selectedURL,
                    onSelect: onSelect,
                    onOpenDiff: onOpenDiff
                )
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled(false)
        .clipped()
    }
}

// MARK: - TreeNodeView

private struct TreeNodeView: View {
    let node: FileNode
    let level: Int
    let showHidden: Bool
    @Binding var selectedURL: URL?
    let onSelect: (URL) -> Void
    let onOpenDiff: ((URL) -> Void)?

    @State private var isExpanded: Bool = true

    /// 过滤掉隐藏文件（除非显示隐藏开关打开）
    private var visibleChildren: [FileNode] {
        showHidden ? node.children : node.children.filter { !$0.isHidden }
    }

    var body: some View {
        if node.isDirectory && node.parent == nil {
            // 根节点：只渲染子节点，不渲染自身
            ForEach(visibleChildren) { child in
                TreeNodeView(
                    node: child,
                    level: level,
                    showHidden: showHidden,
                    selectedURL: $selectedURL,
                    onSelect: onSelect,
                    onOpenDiff: onOpenDiff
                )
            }
        } else if node.isDirectory {
            directoryRow
        } else {
            fileRow
        }
    }

    // MARK: - Directory row

    private var directoryRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // 缩进
                Color.clear
                    .frame(width: CGFloat(level) * 16, height: 0)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Palette.textTertiary)
                    .frame(width: 10)

                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 11))
                    .foregroundColor(isExpanded ? Palette.accent : Palette.textSecond)
                    .frame(width: 16)

                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundColor(directoryNameColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                statusIndicator(for: node.aggregatedStatus)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.trailing, 8)
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }
            .contextMenu {
                Button("添加到 AI 对话") {
                    guard let url = node.url else { return }
                    selectedURL = url
                    DMLogger.log("Enqueue dir: path=\(url.path)", name: "FileTreeView")
                    WorkspaceReferenceBridge.shared.enqueue(
                        path: url.path,
                        isDirectory: true
                    )
                }
            }

            if isExpanded {
                ForEach(visibleChildren) { child in
                    TreeNodeView(
                        node: child,
                        level: level + 1,
                        showHidden: showHidden,
                        selectedURL: $selectedURL,
                        onSelect: onSelect,
                        onOpenDiff: onOpenDiff
                    )
                }
            }
        }
    }

    // MARK: - File row

    private var fileRow: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: CGFloat(level) * 16 + 18, height: 0)

            Image(systemName: fileIcon)
                .font(.system(size: 11))
                .foregroundColor(Palette.textSecond)
                .frame(width: 16)

            Text(node.name)
                .font(.system(size: 12))
                .foregroundColor(fileNameColor)
                .lineLimit(1)
                .truncationMode(.middle)

            statusIndicator(for: node.status)

            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.trailing, 8)
        .background(isSelected ? Palette.bgHover : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = node.url {
                selectedURL = url
                onSelect(url)
            }
        }
        .contextMenu {
            if let onOpenDiff = onOpenDiff, let url = node.url, FileType.classify(url) == .text {
                Button("查看 Diff") {
                    selectedURL = url
                    onOpenDiff(url)
                }
            }

            Button("添加到 AI 对话") {
                guard let url = node.url else { return }
                selectedURL = url
                DMLogger.log("Enqueue file: path=\(url.path) isDir=false", name: "FileTreeView")
                WorkspaceReferenceBridge.shared.enqueue(
                    path: url.path,
                    isDirectory: false
                )
            }
        }
    }

    private var isSelected: Bool {
        guard let url = node.url, let selected = selectedURL else { return false }
        return url.path == selected.path
    }

    private var fileNameColor: Color {
        if node.status == .deleted {
            return Palette.textTertiary
        }
        return isSelected ? Palette.accent : Palette.textPrimary
    }

    private var directoryNameColor: Color {
        return isSelected ? Palette.accent : Palette.textPrimary
    }

    /// 状态徽标：modified 黄色、added 绿色、deleted 红色、ignored 灰色。
    private func statusIndicator(for status: WorkspaceFileStatus) -> some View {
        let color: Color
        switch status {
        case .modified:
            color = Color(red: 1.000, green: 0.600, blue: 0.200)
        case .added:
            color = Color(red: 0.290, green: 0.820, blue: 0.420)
        case .deleted:
            color = Color(red: 0.960, green: 0.380, blue: 0.380)
        case .ignored:
            color = Palette.textTertiary
        case .unchanged:
            color = Color.clear
        }

        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .help(statusHelp(for: status))
    }

    private func statusHelp(for status: WorkspaceFileStatus) -> String {
        switch status {
        case .modified: return "已修改"
        case .added: return "新增"
        case .deleted: return "已删除"
        case .ignored: return "已忽略"
        case .unchanged: return ""
        }
    }

    /// 根据文件扩展名返回 SF Symbol 图标名。
    private var fileIcon: String {
        guard let url = node.url else { return "doc.text" }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift", "kt", "java", "py", "js", "ts", "go", "rs", "c", "cpp", "h", "m", "mm":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "xml", "plist", "toml":
            return "doc.text"
        case "md", "txt", "rst":
            return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "svg", "webp":
            return "photo"
        case "pdf":
            return "pdf"
        default:
            return "doc.text"
        }
    }
}

// MARK: - Palette

private enum Palette {
    static let bgHover     = Color(red: 0.110, green: 0.110, blue: 0.110)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
    static let accent      = Color(red: 0.200, green: 0.600, blue: 1.000)
}