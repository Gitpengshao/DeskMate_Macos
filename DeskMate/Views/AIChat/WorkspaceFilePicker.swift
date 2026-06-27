import SwiftUI

/// 工作区文件选择弹窗 — 在聊天输入框输入 `#` 后触发。
///
/// 允许用户在工作区目录内检索并选择文件路径，
/// 选中后把相对工作区的路径写回输入框。
struct WorkspaceFilePicker: View {
    /// 工作区根目录（绝对路径）。
    let workingDirectory: String
    /// 用户选中文件/目录后的回调，参数为相对路径和是否为目录。
    let onSelect: (String, Bool) -> Void
    /// 取消/关闭弹窗。
    let onCancel: () -> Void

    @State private var searchText: String = ""
    @State private var files: [FileItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private var filteredFiles: [FileItem] {
        if searchText.isEmpty { return files }
        return files.filter { $0.relativePath.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            Palette.scrim
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                header
                Divider().background(Palette.border)
                searchField
                content
                bottomBar
            }
            .frame(width: 520, height: 460)
            .background(Palette.bgPanel)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Palette.border, lineWidth: 1)
            )
        }
        .onAppear { loadFiles() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("选择文件")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(baseName)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.textSecond)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(Palette.textTertiary)
            TextField("搜索文件...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Palette.textPrimary)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.bgBase)
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let error = errorMessage {
            errorView(error)
        } else if isLoading {
            loadingView
        } else if filteredFiles.isEmpty {
            emptyView
        } else {
            fileList
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredFiles) { item in
                    FileRow(
                        item: item,
                        onSelect: { onSelect(item.relativePath, item.isDirectory) }
                    )
                    .id(item.id)
                }
            }
            .padding(.vertical, 4)
        }
        .background(Palette.bgBase)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(Palette.textPrimary)
            Text("正在扫描工作区...")
                .font(.system(size: 12))
                .foregroundColor(Palette.textSecond)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgBase)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28))
                .foregroundColor(Palette.textTertiary)
            Text(searchText.isEmpty ? "工作区暂无文件" : "未找到匹配文件")
                .font(.system(size: 12))
                .foregroundColor(Palette.textSecond)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgBase)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(Palette.textTertiary)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(Palette.textSecond)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgBase)
    }

    private var bottomBar: some View {
        HStack {
            Text("\(filteredFiles.count) 个结果")
                .font(.system(size: 11))
                .foregroundColor(Palette.textTertiary)
            Spacer()
            Button(action: onCancel) {
                Text("取消")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Palette.textSecond)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private var baseName: String {
        (workingDirectory as NSString).lastPathComponent
    }

    private func loadFiles() {
        isLoading = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) {
            do {
                let fm = FileManager.default
                let base = (self.workingDirectory as NSString).standardizingPath
                let baseURL = URL(fileURLWithPath: base)

                guard fm.fileExists(atPath: base) else {
                    await MainActor.run {
                        self.errorMessage = "工作区目录不存在"
                        self.isLoading = false
                    }
                    return
                }

                let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
                let enumerator = fm.enumerator(
                    at: baseURL,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )

                var items: [FileItem] = []
                let maxCount = 5000
                while let fileURL = enumerator?.nextObject() as? URL {
                    let relativePath = relativePath(for: fileURL, baseDirectory: base)
                    let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    items.append(FileItem(relativePath: relativePath, isDirectory: isDir))
                    if items.count >= maxCount { break }
                }

                let sorted = items.sorted {
                    if $0.isDirectory != $1.isDirectory {
                        return $0.isDirectory && !$1.isDirectory
                    }
                    return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
                }

                await MainActor.run {
                    self.files = sorted
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "读取文件失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func relativePath(for fileURL: URL, baseDirectory: String) -> String {
        let filePath = fileURL.path
        guard filePath.hasPrefix(baseDirectory) else { return filePath }
        let index = filePath.index(filePath.startIndex, offsetBy: baseDirectory.count)
        let remainder = String(filePath[index...])
        return remainder.hasPrefix("/") ? String(remainder.dropFirst()) : remainder
    }
}

// MARK: - FileRow

private struct FileRow: View {
    let item: FileItem
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: item.isDirectory ? "folder" : "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecond)
                    .frame(width: 16)
                Text(item.relativePath)
                    .font(.system(size: 13))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Palette.bgHover : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - FileItem

private struct FileItem: Identifiable, Equatable {
    let id = UUID()
    let relativePath: String
    let isDirectory: Bool
}

// MARK: - Palette

private enum Palette {
    static let bgBase      = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let bgHover     = Color(red: 0.110, green: 0.110, blue: 0.110)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
    static let scrim       = Color(red: 0.000, green: 0.000, blue: 0.000).opacity(0.6)
}
