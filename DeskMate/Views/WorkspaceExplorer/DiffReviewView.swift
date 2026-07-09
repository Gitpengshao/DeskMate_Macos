import SwiftUI

/// 文件 diff 统一审查视图 — 支持 hunk / 行 / 整文件接受与拒绝。
///
/// 数据来源可以是 Git 仓库，也可以是本地基线与当前内容对比。
struct DiffReviewView: View {
    @StateObject private var viewModel: DiffReviewViewModel

    init(
        source: DiffSource,
        fileURL: URL,
        onApply: @MainActor @escaping (String) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: DiffReviewViewModel(
            source: source,
            fileURL: fileURL,
            onApply: onApply
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.border)
            content
        }
        .background(Palette.bgBase)
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textSecond)
                    Text(viewModel.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                }

                Text(viewModel.displayPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(Palette.textPrimary)
            } else {
                diffStats
                fileActionButtons
                statusMessageView
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.bgPanel)
    }

    private var diffStats: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DiffPalette.addedForeground)
                Text("\(viewModel.additions)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DiffPalette.addedForeground)
            }

            HStack(spacing: 4) {
                Image(systemName: "minus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(DiffPalette.deletedForeground)
                Text("\(viewModel.deletions)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DiffPalette.deletedForeground)
            }
        }
    }

    private var fileActionButtons: some View {
        HStack(spacing: 6) {
            actionButton(title: "接受文件", icon: "checkmark", color: DiffPalette.addedForeground) {
                viewModel.setFileAction(.accepted)
            }
            .disabled(viewModel.fileAction == .accepted)

            actionButton(title: "拒绝文件", icon: "xmark", color: DiffPalette.deletedForeground) {
                viewModel.setFileAction(.rejected)
            }
            .disabled(viewModel.fileAction == .rejected)
        }
    }

    private var statusMessageView: some View {
        Group {
            if let success = viewModel.successMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DiffPalette.addedForeground)
                    Text(success)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DiffPalette.addedForeground)
                }
            } else if let error = viewModel.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(DiffPalette.deletedForeground)
                    Text(error)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DiffPalette.deletedForeground)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .scaleEffect(0.8)
                .tint(Palette.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundColor(Palette.textTertiary)
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecond)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let diff = viewModel.diff {
            diffContent(diff: diff)
        } else {
            emptyPlaceholder
        }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(Palette.textTertiary)
            Text("没有可审查的修改")
                .font(.system(size: 13))
                .foregroundColor(Palette.textSecond)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func diffContent(diff: GitDiff) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.files.enumerated()), id: \.offset) { _, file in
                    fileDiffView(file: file, showPathHeader: diff.files.count > 1)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func fileDiffView(file: DiffFile, showPathHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showPathHeader {
                Text(file.displayPath)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Palette.bgPanel)
            }

            ForEach(Array(file.hunks.enumerated()), id: \.offset) { index, hunk in
                VStack(alignment: .leading, spacing: 0) {
                    DiffHunkHeaderView(
                        hunk: hunk,
                        action: viewModel.hunkActions[index] ?? .default,
                        onAccept: { viewModel.setHunkAction(.accepted, at: index) },
                        onReject: { viewModel.setHunkAction(.rejected, at: index) }
                    )

                    ForEach(hunk.lines) { line in
                        if line.kind == .context {
                            DiffContextLineRowView(line: line)
                        } else if line.kind != .hunkHeader {
                            DiffLineRowView(
                                line: line,
                                action: viewModel.effectiveAction(for: line),
                                onAccept: { viewModel.setLineAction(.accepted, for: line) },
                                onReject: { viewModel.setLineAction(.rejected, for: line) }
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Context Line Row

/// 未变更的 context 行：只显示行号与内容，无接受/拒绝按钮。
private struct DiffContextLineRowView: View {
    let line: DiffLine

    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let lineHeight: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            lineNumberCell(value: line.oldLineNumber, width: 48, alignment: .trailing)
            Divider().background(Palette.border)
            lineNumberCell(value: line.newLineNumber, width: 48, alignment: .trailing)
            Divider().background(Palette.border)

            Text(" ")
                .font(Font(font))
                .frame(width: 16, alignment: .center)

            Text(line.text)
                .font(Font(font))
                .foregroundColor(Palette.textPrimary)
                .lineSpacing(0)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: lineHeight)
        .background(Palette.bgBase)
    }

    private func lineNumberCell(value: Int?, width: CGFloat, alignment: Alignment) -> some View {
        Text(value.map { "\($0)" } ?? "")
            .font(Font(NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)))
            .foregroundColor(Palette.textTertiary)
            .frame(width: width, height: lineHeight, alignment: alignment)
            .padding(.horizontal, 4)
            .background(Palette.bgPanel)
    }
}

// MARK: - Helpers

private extension DiffReviewView {
    func actionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(color)
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
}

enum DiffPalette {
    static let addedBackground    = Color(red: 0.118, green: 0.294, blue: 0.173)
    static let addedForeground    = Color(red: 0.290, green: 0.820, blue: 0.420)
    static let deletedBackground  = Color(red: 0.337, green: 0.118, blue: 0.118)
    static let deletedForeground  = Color(red: 0.960, green: 0.380, blue: 0.380)
    static let hunkHeaderBackground = Color(red: 0.078, green: 0.137, blue: 0.196)
    static let hunkHeaderForeground = Color(red: 0.500, green: 0.700, blue: 0.900)
}
