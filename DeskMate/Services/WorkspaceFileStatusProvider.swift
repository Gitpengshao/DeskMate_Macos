import Foundation

/// 工作区文件变更状态。
enum WorkspaceFileStatus: Equatable {
    case unchanged
    case modified
    case added
    case deleted
    case ignored
}

/// 计算工作区中文件/目录的变更状态。
///
/// - Git 仓库：使用 `git status --porcelain` 的结果。
/// - 非 Git 仓库：通过比较磁盘内容与 `LocalHistoryStore` 最新快照判断。
actor WorkspaceFileStatusProvider {
    static let shared = WorkspaceFileStatusProvider()

    private var gitStatusCache: [String: [String: WorkspaceFileStatus]] = [:]

    // MARK: - 公共 API

    /// 计算单个文件/目录的状态。
    func status(for url: URL, in workspace: String) async -> WorkspaceFileStatus {
        let standardizedWorkspace = (workspace as NSString).standardizingPath
        let gitDir = (standardizedWorkspace as NSString).appendingPathComponent(".git")
        let isGitRepo = FileManager.default.fileExists(atPath: gitDir)

        if isGitRepo {
            return await gitStatus(for: url, in: standardizedWorkspace)
        } else {
            return await localStatus(for: url, in: standardizedWorkspace)
        }
    }

    /// 批量计算整个工作区的状态。
    func statuses(in workspace: String) async -> [String: WorkspaceFileStatus] {
        let standardizedWorkspace = (workspace as NSString).standardizingPath
        let gitDir = (standardizedWorkspace as NSString).appendingPathComponent(".git")
        let isGitRepo = FileManager.default.fileExists(atPath: gitDir)

        if isGitRepo {
            return await gitStatuses(in: standardizedWorkspace)
        } else {
            return [:] // 非 Git 目录按需单文件计算，避免大目录扫描
        }
    }

    // MARK: - Git 状态

    private func gitStatus(for url: URL, in workspace: String) async -> WorkspaceFileStatus {
        let statuses = await gitStatuses(in: workspace)
        let relativePath = self.relativePath(for: url, workspace: workspace)
        guard let relativePath = relativePath else { return .unchanged }

        // 优先精确匹配
        if let status = statuses[relativePath] {
            return status
        }

        // 目录：若任何子路径有变更，目录视为 modified
        for (path, status) in statuses {
            if path.hasPrefix(relativePath + "/"), status != .unchanged {
                return .modified
            }
        }

        return .unchanged
    }

    private func gitStatuses(in workspace: String) async -> [String: WorkspaceFileStatus] {
        if let cached = gitStatusCache[workspace] {
            return cached
        }

        let entries = await GitCommandService.status(workingDirectory: workspace)
        var result: [String: WorkspaceFileStatus] = [:]

        for entry in entries {
            let code = entry.status
            let path = entry.path

            let status: WorkspaceFileStatus
            if code.hasPrefix("!!") {
                status = .ignored
            } else if code.contains("D") {
                status = .deleted
            } else if code.contains("A") || code == "??" {
                status = .added
            } else if code.contains("M") || code.contains("R") || code.contains("C") {
                status = .modified
            } else {
                status = .unchanged
            }

            result[path] = status
        }

        gitStatusCache[workspace] = result
        return result
    }

    /// 清空 Git 状态缓存，通常在文件变更后调用。
    func invalidateGitCache(for workspace: String) {
        gitStatusCache.removeValue(forKey: (workspace as NSString).standardizingPath)
    }

    // MARK: - 非 Git 本地状态

    private func localStatus(for url: URL, in workspace: String) async -> WorkspaceFileStatus {
        let relativePath = self.relativePath(for: url, workspace: workspace)
        guard let relativePath = relativePath else { return .unchanged }

        let fileExists = FileManager.default.fileExists(atPath: url.path)
        let latestSnapshot = await LocalHistoryStore.shared.latestSnapshot(workspace: workspace, filePath: url.path)

        if !fileExists {
            return latestSnapshot != nil ? .deleted : .unchanged
        }

        guard let snapshot = latestSnapshot else {
            return .unchanged
        }

        do {
            let diskContent = try String(contentsOf: url, encoding: .utf8)
            return diskContent == snapshot.content ? .unchanged : .modified
        } catch {
            return .unchanged
        }
    }

    // MARK: - 辅助

    private func relativePath(for url: URL, workspace: String) -> String? {
        let path = (url.path as NSString).standardizingPath
        let base = (workspace as NSString).standardizingPath
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
    }
}
