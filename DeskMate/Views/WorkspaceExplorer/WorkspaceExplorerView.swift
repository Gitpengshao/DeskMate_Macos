import SwiftUI
import AppKit

/// 工作区浏览器主视图 — 左侧文件树 + 右侧多标签编辑器。
///
/// 行为约定:
/// - 文本/代码文件:点击后在右侧打开为新 Tab(已打开则聚焦),并在标签栏中并列显示。
/// - 二进制文件(图片、PDF、音频、视频、压缩包、可执行文件等):不读取为文本,
///   在右侧显示「无法在编辑器中打开」的占位视图,并提供「在默认应用中打开」入口。
struct WorkspaceExplorerView: View {
    let workingDirectory: String

    @State private var fileTreeRoot: FileNode?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showHiddenFiles = false

    // 多标签状态
    @State private var openTabs: [FileTab] = []
    @State private var activeTabId: UUID?
    // 当前在右侧展示的 URL(可能指向某个 Tab,也可能指向无法打开的二进制文件)
    @State private var selectedURL: URL?

    var body: some View {
        HSplitView {
            fileTreePanel
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 400)

            rightPanel
                .frame(minWidth: 300, idealWidth: .infinity)
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Palette.bgBase)
        .onAppear {
            Task { @MainActor in
                loadFileTree()
            }
        }
    }

    // MARK: - Left panel: File tree

    private var fileTreePanel: some View {
        VStack(spacing: 0) {
            fileTreeHeader

            Divider().background(Palette.border)

            if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(Palette.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let root = fileTreeRoot {
                FileTreeView(
                    node: root,
                    showHidden: showHiddenFiles,
                    selectedURL: $selectedURL,
                    onSelect: selectFile
                )
            } else if let err = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 20))
                        .foregroundColor(Palette.textTertiary)
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textSecond)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyTreePlaceholder
            }
        }
        .background(Palette.bgPanel)
    }

    private var fileTreeHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundColor(Palette.textSecond)
            Text(basename)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // 把当前选中的文件/目录推入 AI 对话 — 仅在有选中项时可用
            addToAIButton

            Toggle(isOn: $showHiddenFiles) {
                Image(systemName: "eye")
                    .font(.system(size: 10))
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundColor(showHiddenFiles ? Palette.textPrimary : Palette.textTertiary)
            .help("显示隐藏文件")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// "添加到 AI 对话" 按钮 — 仅在有选中项时启用。
    ///
    /// 使用 `selectedURL`：若存在，先用 `FileManager` 判定是否为目录，
    /// 然后把绝对路径推入 `WorkspaceReferenceBridge`，由主窗口中的
    /// `AiChatPage` 订阅消费。
    @ViewBuilder
    private var addToAIButton: some View {
        let hasSelection = selectedURL != nil
        Button(action: addSelectedToAI) {
            Image(systemName: "plus.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(hasSelection ? Palette.textPrimary : Palette.textTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!hasSelection)
        .help(hasSelection
              ? "把当前选中的文件/目录添加到 AI 对话"
              : "请先在左侧选择文件或目录")
    }

    private func addSelectedToAI() {
        guard let url = selectedURL else { return }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists else { return }
        DMLogger.log(
            "Enqueue selected: path=\(url.path) fmIsDir=\(isDir.boolValue)",
            name: "WorkspaceExplorerView"
        )
        WorkspaceReferenceBridge.shared.enqueue(
            path: url.path,
            isDirectory: isDir.boolValue
        )
    }

    private var emptyTreePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28))
                .foregroundColor(Palette.textTertiary)
            Text("目录为空或无法访问")
                .font(.system(size: 12))
                .foregroundColor(Palette.textSecond)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Right panel: Tab bar + content

    private var rightPanel: some View {
        VStack(spacing: 0) {
            tabBar

            Divider().background(Palette.border)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.bgBase)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let active = activeTab {
            CodeEditorView(
                fileURL: active.url,
                content: bindingForTab(active).content,
                isDirty: bindingForTab(active).isDirty
            )
            .id(active.id)
        } else if let url = selectedURL, FileType.classify(url) == .binary {
            UnsupportedFileView(url: url)
        } else {
            welcomePlaceholder
        }
    }

    private var welcomePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(Palette.textTertiary)
            Text("选择一个文件以开始编辑")
                .font(.system(size: 14))
                .foregroundColor(Palette.textSecond)
            Text("左侧文件树中点击任意文本/代码文件即可在标签中打开")
                .font(.system(size: 11))
                .foregroundColor(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgBase)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            if openTabs.isEmpty {
                Text("无打开的文件")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(openTabs) { tab in
                            TabItemView(
                                tab: tab,
                                isActive: tab.id == activeTabId,
                                onActivate: { activateTab(tab) },
                                onClose: { closeTab(tab) }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(height: 34)
        .background(Palette.bgPanel)
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Tab data helpers

    private var activeTab: FileTab? {
        guard let id = activeTabId else { return nil }
        return openTabs.first(where: { $0.id == id })
    }

    /// 为指定 Tab 构造子 Binding,供 CodeEditorView 双向绑定内容与未保存状态。
    private func bindingForTab(_ tab: FileTab) -> (content: Binding<String>, isDirty: Binding<Bool>) {
        guard let index = openTabs.firstIndex(where: { $0.id == tab.id }) else {
            return (.constant(tab.content), .constant(tab.isDirty))
        }
        return (
            $openTabs[index].content,
            $openTabs[index].isDirty
        )
    }

    private func activateTab(_ tab: FileTab) {
        activeTabId = tab.id
        selectedURL = tab.url
    }

    private func closeTab(_ tab: FileTab) {
        guard let index = openTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        openTabs.remove(at: index)

        if activeTabId == tab.id {
            if openTabs.isEmpty {
                activeTabId = nil
                // 保留 selectedURL:若用户正在预览二进制文件,继续显示占位视图
            } else {
                let newIndex = min(index, openTabs.count - 1)
                let newTab = openTabs[newIndex]
                activeTabId = newTab.id
                selectedURL = newTab.url
            }
        }
    }

    // MARK: - File tree loading

    private func loadFileTree() {
        isLoading = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) {
            let base = (self.workingDirectory as NSString).standardizingPath
            let baseURL = URL(fileURLWithPath: base)
            guard FileManager.default.fileExists(atPath: base) else {
                await MainActor.run {
                    self.errorMessage = "工作区目录不存在"
                    self.isLoading = false
                }
                return
            }

            let root = FileNode(url: baseURL)

            let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .localizedNameKey]
            let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants]
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                      let isDir = values.isDirectory,
                      let isHidden = values.isHidden
                else { continue }

                if isHidden && isDir { continue }

                let relativePath = fileURL.path
                    .replacingOccurrences(of: base + "/", with: "")
                let components = relativePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                root.insert(pathComponents: components, isDirectory: isDir, isHidden: isHidden, url: fileURL)
            }

            root.sortChildren()

            await MainActor.run {
                self.fileTreeRoot = root
                self.isLoading = false
            }
        }
    }

    // MARK: - File selection

    /// 文件树点击的统一入口 — 先判断文件类型,再决定行为。
    ///
    /// - 文本/代码文件:若已存在 Tab 则聚焦,否则新建 Tab 并加载内容。
    /// - 二进制文件:不读取为文本,在右侧显示占位视图,不污染 Tab 列表。
    private func selectFile(_ url: URL) {
        // FileTreeView 已经将 selectedURL 同步为 url,这里只决定是否打开 Tab。
        switch FileType.classify(url) {
        case .text:
            if let existing = openTabs.first(where: { $0.url == url }) {
                activateTab(existing)
            } else {
                openFileInNewTab(url)
            }
        case .binary:
            // 清掉活动 Tab,使右侧显示 UnsupportedFileView
            activeTabId = nil
        }
    }

    private func openFileInNewTab(_ url: URL) {
        // 同步读取文件内容 — 让 SourceEditor 在 makeNSView 时就拿到完整字符串。
        // 若先以空串占位再异步回填,CodeEditSourceEditor 的 NSViewRepresentable 包装层
        // 不会把后续 binding 更新可靠地推送到内部 NSTextView,会出现"语法高亮语言已加载
        // 但内容空白"的现象。
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            content = "// 无法读取文件内容:\(error.localizedDescription)"
        }

        let tab = FileTab(url: url, content: content, isDirty: false)
        openTabs.append(tab)
        activeTabId = tab.id
    }

    private var basename: String {
        (workingDirectory as NSString).lastPathComponent
    }
}

// MARK: - TabItemView

/// 单个文件选项卡的可视化。
private struct TabItemView: View {
    let tab: FileTab
    let isActive: Bool
    let onActivate: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundColor(isActive ? Palette.textPrimary : Palette.textTertiary)

            Text(tab.displayName)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? Palette.textPrimary : Palette.textSecond)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160)

            if tab.isDirty {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 6, height: 6)
                    .help("有未保存的修改")
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isActive ? Palette.textSecond : Palette.textTertiary)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(Color.clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭标签")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Palette.bgElevated : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Palette.border : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
    }
}

// MARK: - UnsupportedFileView

/// 二进制文件占位视图 — 明确告诉用户此文件不能在编辑器中打开,
/// 并提供「在默认应用中打开」的快捷入口。
private struct UnsupportedFileView: View {
    let url: URL

    private var fileSizeText: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return "未知大小"
        }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "eye.slash")
                .font(.system(size: 40))
                .foregroundColor(Palette.textTertiary)

            Text(url.lastPathComponent)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            VStack(spacing: 4) {
                Text("此文件类型不能在代码编辑器中打开")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecond)
                Text("\(FileType.displayName(for: url)) · \(fileSizeText)")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
            }

            Text(url.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Palette.textTertiary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, 24)
                .help(url.path)

            Button(action: openWithDefaultApp) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                    Text("在默认应用中打开")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Palette.bgElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Palette.border, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgBase)
    }

    private func openWithDefaultApp() {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - FileNode

/// 文件树节点 — 用于构建目录层级。
final class FileNode: Identifiable {
    let id = UUID()
    let name: String
    let url: URL?
    let isDirectory: Bool
    let isHidden: Bool
    var children: [FileNode] = []
    weak var parent: FileNode?

    init(name: String, url: URL?, isDirectory: Bool, isHidden: Bool = false) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.isHidden = isHidden
    }

    convenience init(url: URL) {
        let name = url.lastPathComponent
        self.init(name: name, url: url, isDirectory: true, isHidden: false)
    }

    func insert(pathComponents: [String], isDirectory: Bool, isHidden: Bool, url: URL) {
        guard !pathComponents.isEmpty else { return }
        let head = String(pathComponents[0])
        let tail = Array(pathComponents.dropFirst())

        if let existing = children.first(where: { $0.name == head }) {
            if !tail.isEmpty {
                existing.insert(pathComponents: tail, isDirectory: isDirectory, isHidden: isHidden, url: url)
            }
        } else {
            let node = FileNode(
                name: head,
                url: tail.isEmpty ? url : nil,
                isDirectory: tail.isEmpty ? isDirectory : true,
                isHidden: isHidden
            )
            node.parent = self
            children.append(node)
            if !tail.isEmpty {
                node.insert(pathComponents: tail, isDirectory: isDirectory, isHidden: isHidden, url: url)
            }
        }
    }

    func sortChildren() {
        children.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        children.forEach { $0.sortChildren() }
    }
}

// MARK: - Palette

private enum Palette {
    static let bgBase      = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let bgElevated  = Color(red: 0.078, green: 0.078, blue: 0.078)
    static let bgHover     = Color(red: 0.110, green: 0.110, blue: 0.110)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
    static let accent      = Color(red: 0.200, green: 0.600, blue: 1.000)
}
