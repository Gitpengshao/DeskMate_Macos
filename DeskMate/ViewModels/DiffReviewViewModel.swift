import Combine
import Foundation
import SwiftUI

/// Diff 审查视图的状态与业务逻辑。
@MainActor
final class DiffReviewViewModel: ObservableObject {
    let source: DiffSource
    let fileURL: URL
    let onApply: @MainActor (String) -> Void

    @Published private(set) var diff: GitDiff?
    @Published private(set) var baseContent: String = ""
    @Published private(set) var proposedContent: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?

    /// 整文件显式决定。
    @Published var fileAction: DiffAction = .default
    /// Hunk 级显式决定。
    @Published var hunkActions: [Int: DiffAction] = [:]
    /// 行级显式决定。
    @Published var lineActions: [DiffLineKey: DiffAction] = [:]

    init(
        source: DiffSource,
        fileURL: URL,
        onApply: @MainActor @escaping (String) -> Void = { _ in }
    ) {
        self.source = source
        self.fileURL = fileURL
        self.onApply = onApply
    }

    // MARK: - 计算属性

    var fileName: String { fileURL.lastPathComponent }

    var displayPath: String { fileURL.path }

    var additions: Int {
        guard let diff else { return 0 }
        return diff.files.reduce(0) { count, file in
            count + file.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count }
        }
    }

    var deletions: Int {
        guard let diff else { return 0 }
        return diff.files.reduce(0) { count, file in
            count + file.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deleted }.count }
        }
    }

    var hasExplicitRejection: Bool {
        if fileAction.effective == .rejected { return true }
        if hunkActions.values.contains(where: { $0.effective == .rejected }) { return true }
        if lineActions.values.contains(where: { $0.effective == .rejected }) { return true }
        return false
    }

    var hasChanges: Bool {
        additions > 0 || deletions > 0 ||
        fileAction != .default ||
        !hunkActions.isEmpty ||
        !lineActions.isEmpty
    }

    var isGitMode: Bool {
        if case .git = source { return true }
        return false
    }

    // MARK: - 加载

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        switch source {
        case .git(let workingDirectory):
            await loadGit(workingDirectory: workingDirectory)
        case .local(let baseContent, let proposedContent, let isNew):
            await loadLocal(baseContent: baseContent, proposedContent: proposedContent, isNew: isNew)
        }
    }

    private func loadGit(workingDirectory: String) async {
        let isRepo = await GitCommandService.isGitRepository(at: workingDirectory)
        guard isRepo else {
            errorMessage = "当前工作区不是 Git 仓库"
            return
        }

        let relativePath = relativePath(for: fileURL, workingDirectory: workingDirectory)

        // 读取基准版本与工作区版本
        if let base = await GitCommandService.baseContent(
            workingDirectory: workingDirectory,
            path: relativePath
        ) {
            self.baseContent = base
        } else {
            self.baseContent = ""
        }

        do {
            self.proposedContent = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            self.proposedContent = ""
        }

        let rawDiff = await GitCommandService.diff(
            workingDirectory: workingDirectory,
            path: relativePath,
            contextLines: 3
        )

        let parsed: GitDiff
        if rawDiff.isEmpty && proposedContent != baseContent {
            // 可能是未跟踪的新文件：git diff 默认不输出，构造全量新增 diff
            parsed = syntheticDiffForUntracked(relativePath: relativePath)
        } else {
            parsed = DiffParser.parse(rawDiff)
        }
        self.diff = parsed

        clearActions()

        if parsed.files.first?.isBinary == true {
            errorMessage = "二进制文件不支持逐行审查，请使用顶部按钮接受或拒绝整个文件"
            return
        }

        if parsed.files.isEmpty && proposedContent == baseContent {
            errorMessage = "该文件没有可审查的修改"
        }
    }

    private func loadLocal(baseContent: String, proposedContent: String, isNew: Bool) async {
        self.baseContent = baseContent
        self.proposedContent = proposedContent

        let relativePath = fileURL.lastPathComponent

        DMLogger.log("DiffReviewViewModel loadLocal: baseLength=\(baseContent.count), proposedLength=\(proposedContent.count), isNew=\(isNew)", name: "DiffDebug")

        let rawDiff = TextDiffer.unifiedDiff(
            old: baseContent,
            new: proposedContent,
            path: relativePath,
            contextLines: 3
        )

        DMLogger.log("DiffReviewViewModel loadLocal: rawDiff length=\(rawDiff.count), empty=\(rawDiff.isEmpty)", name: "DiffDebug")

        var parsed: GitDiff
        if rawDiff.isEmpty && proposedContent != baseContent {
            parsed = syntheticDiffForUntracked(relativePath: relativePath)
        } else {
            parsed = DiffParser.parse(rawDiff)
        }

        // 非 Git 模式下需要自行补全 isNew / isDeleted / isBinary 标记。
        let isBinary = FileType.classify(fileURL) == .binary
        if var file = parsed.files.first {
            file = DiffFile(
                oldPath: file.oldPath,
                newPath: file.newPath,
                hunks: file.hunks,
                isNew: isNew || file.isNew,
                isDeleted: proposedContent.isEmpty && !baseContent.isEmpty,
                isBinary: isBinary || file.isBinary
            )
            parsed = GitDiff(files: [file])
        }

        self.diff = parsed
        clearActions()

        DMLogger.log("DiffReviewViewModel loadLocal: parsed files=\(parsed.files.count), hunks=\(parsed.files.first?.hunks.count ?? 0)", name: "DiffDebug")

        if isBinary {
            errorMessage = "二进制文件不支持逐行审查，请使用顶部按钮接受或拒绝整个文件"
            return
        }

        if parsed.files.isEmpty && proposedContent == baseContent {
            errorMessage = "该文件没有可审查的修改"
            DMLogger.log("DiffReviewViewModel loadLocal: no changes detected", name: "DiffDebug")
        }
    }

    private func clearActions() {
        self.fileAction = .default
        self.hunkActions.removeAll()
        self.lineActions.removeAll()
    }

    /// 为未跟踪的新文件构造一个全量新增的 synthetic diff。
    private func syntheticDiffForUntracked(relativePath: String) -> GitDiff {
        let lines = LineEnding.splitLines(proposedContent)
        let count = lines.count
        let newStart = count > 0 ? 1 : 0
        let header = "@@ -0,0 +\(newStart),\(count) @@"
        let hunkLines: [DiffLine] = [
            DiffLine(
                kind: .hunkHeader,
                text: header,
                oldLineNumber: nil,
                newLineNumber: nil,
                hunkIndex: 0,
                lineIndexInHunk: 0
            )
        ] + lines.enumerated().map { index, text in
            DiffLine(
                kind: .added,
                text: text,
                oldLineNumber: nil,
                newLineNumber: index + 1,
                hunkIndex: 0,
                lineIndexInHunk: index + 1
            )
        }

        let file = DiffFile(
            oldPath: relativePath,
            newPath: relativePath,
            hunks: [
                DiffHunk(
                    oldStart: 0,
                    oldCount: 0,
                    newStart: newStart,
                    newCount: count,
                    header: header,
                    lines: hunkLines
                )
            ],
            isNew: true,
            isDeleted: false,
            isBinary: false
        )
        return GitDiff(files: [file])
    }

    // MARK: - 动作设置

    func setFileAction(_ action: DiffAction) {
        fileAction = action
        // 文件级决定覆盖下层
        hunkActions.removeAll()
        lineActions.removeAll()
        Task { await applyChanges() }
    }

    func setHunkAction(_ action: DiffAction, at index: Int) {
        hunkActions[index] = action
        // 清除该 hunk 内的行级决定
        lineActions = lineActions.filter { $0.key.hunkIndex != index }
        // 文件级决定失效
        fileAction = .default
        Task { await applyChanges() }
    }

    func setLineAction(_ action: DiffAction, for line: DiffLine) {
        guard line.kind == .added || line.kind == .deleted else { return }
        lineActions[DiffLineKey(hunkIndex: line.hunkIndex, lineIndexInHunk: line.lineIndexInHunk)] = action
        fileAction = .default
        Task { await applyChanges() }
    }

    /// 计算某一行的有效决定。
    func effectiveAction(for line: DiffLine) -> DiffAction {
        guard line.kind == .added || line.kind == .deleted else { return .default }

        let key = DiffLineKey(hunkIndex: line.hunkIndex, lineIndexInHunk: line.lineIndexInHunk)
        if let action = lineActions[key], action != .default {
            return action
        }
        if let action = hunkActions[line.hunkIndex], action != .default {
            return action
        }
        if fileAction != .default {
            return fileAction
        }
        return .accepted
    }

    // MARK: - 应用变更

    /// 把用户决定写入磁盘。返回是否成功。
    @discardableResult
    func applyChanges() async -> Bool {
        guard let diff else { return false }
        isApplying = true
        defer { isApplying = false }
        successMessage = nil
        errorMessage = nil

        switch source {
        case .git(let workingDirectory):
            return await applyGitChanges(diff: diff, workingDirectory: workingDirectory)
        case .local:
            return await applyLocalChanges(diff: diff)
        }
    }

    private func applyGitChanges(diff: GitDiff, workingDirectory: String) async -> Bool {
        let relativePath = relativePath(for: fileURL, workingDirectory: workingDirectory)
        let file = diff.files.first

        // 整文件级快捷路径
        if fileAction == .accepted {
            let ok = await GitCommandService.acceptFile(
                workingDirectory: workingDirectory,
                path: relativePath
            )
            await finalizeApply(ok: ok, success: "已接受并暂存文件")
            return ok
        }

        if fileAction == .rejected {
            let ok: Bool
            if file?.isNew == true {
                // 拒绝新增文件 = 删除（文件可能已被外部删除，先检查存在性）
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                        ok = true
                    } catch {
                        errorMessage = "删除文件失败: \(error.localizedDescription)"
                        ok = false
                    }
                } else {
                    ok = true
                }
            } else {
                ok = await GitCommandService.rejectFile(
                    workingDirectory: workingDirectory,
                    path: relativePath
                )
            }
            await finalizeApply(ok: ok, success: "已拒绝并还原文件")
            return ok
        }

        // 混合决定：从 baseContent 重新合成
        let finalContent = reconstructContent(diff: diff)

        // 如果文件在 HEAD 中存在且合成结果为空，视为删除
        if finalContent.isEmpty, !(file?.isNew ?? true) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch {
                    errorMessage = "删除文件失败: \(error.localizedDescription)"
                    return false
                }
            }
            _ = await GitCommandService.acceptFile(
                workingDirectory: workingDirectory,
                path: relativePath
            )
            await finalizeApply(ok: true, success: "已删除文件并暂存")
            return true
        }

        let written = GitCommandService.writeFile(at: fileURL.path, content: finalContent)
        guard written else {
            errorMessage = "无法写入文件"
            return false
        }

        _ = await GitCommandService.acceptFile(
            workingDirectory: workingDirectory,
            path: relativePath
        )

        await finalizeApply(ok: true, success: "已应用选择并暂存")
        return true
    }

    private func applyLocalChanges(diff: GitDiff) async -> Bool {
        let file = diff.files.first

        // 整文件接受：保留当前内容
        if fileAction == .accepted {
            onApply(proposedContent)
            return true
        }

        // 整文件拒绝：恢复基线
        if fileAction == .rejected {
            if file?.isNew == true {
                // 新增文件拒绝 = 删除
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                    } catch {
                        errorMessage = "删除文件失败: \(error.localizedDescription)"
                        return false
                    }
                }
                onApply("")
                return true
            }

            onApply(baseContent)
            return true
        }

        // 混合决定：从 baseContent 重新合成
        let finalContent = reconstructContent(diff: diff)

        // 非 Git 模式下，若合成结果为空且不是新增文件，则删除文件
        if finalContent.isEmpty, !(file?.isNew ?? true) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch {
                    errorMessage = "删除文件失败: \(error.localizedDescription)"
                    return false
                }
            }
            onApply("")
            return true
        }

        onApply(finalContent)
        return true
    }

    private func finalizeApply(ok: Bool, success: String) async {
        if ok {
            successMessage = success
            await load()
            scheduleClearSuccessMessage()
        }
    }

    private func finalizeLocalApply(finalContent: String, success: String) async {
        successMessage = success
        // 本地模式应用后，基线与当前内容都变为最终结果，diff 清空。
        self.baseContent = finalContent
        self.proposedContent = finalContent
        self.diff = nil
        clearActions()
        scheduleClearSuccessMessage()
    }

    private func scheduleClearSuccessMessage() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            successMessage = nil
        }
    }

    // MARK: - 内容重建

    /// 根据 baseContent、diff 与各层级决定，重建最终文件内容。
    private func reconstructContent(diff: GitDiff) -> String {
        guard let file = diff.files.first else { return proposedContent }

        var baseLines = LineEnding.splitLines(baseContent)
        // 新增文件没有 baseContent，换行符信息从 proposedContent 获取；
        // 既有文件则以 baseContent 为准，确保部分接受后换行符不变。
        let endingReference = file.isNew ? proposedContent : baseContent
        let baseLineEnding = LineEnding.detect(in: endingReference)
        let hasTrailingNewline = !endingReference.isEmpty && endingReference.hasSuffix(baseLineEnding)

        // 从底部向上处理 hunk，避免行号偏移
        let sortedHunks = file.hunks.sorted { $0.oldStart > $1.oldStart }

        for hunk in sortedHunks {
            let start = max(0, hunk.oldStart - 1)
            let end = min(baseLines.count, start + hunk.oldCount)
            var replacement: [String] = []

            for line in hunk.lines where line.kind != .hunkHeader && line.kind != .noNewlineAtEnd {
                let action = effectiveAction(for: line)
                switch line.kind {
                case .context:
                    replacement.append(line.text)
                case .added:
                    if action == .accepted {
                        replacement.append(line.text)
                    }
                case .deleted:
                    if action == .rejected {
                        replacement.append(line.text)
                    }
                default:
                    break
                }
            }

            baseLines.replaceSubrange(start..<end, with: replacement)
        }

        return LineEnding.joinLines(baseLines, ending: baseLineEnding, trailing: hasTrailingNewline)
    }

    private func relativePath(for url: URL, workingDirectory: String) -> String {
        let base = (workingDirectory as NSString).standardizingPath
        let path = url.path
        if path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        return path
    }
}
