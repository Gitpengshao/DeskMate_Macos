import Foundation
import CryptoKit

/// 跨会话本地历史存储 — 为工作区文件保存内容快照，实现 Cursor/Trae 式的历史回溯。
///
/// 存储路径：`~/Library/Application Support/DeskMate/local-history/<workspace-hash>/<relative-path>/<timestamp>.json`
actor LocalHistoryStore {
    static let shared = LocalHistoryStore()

    private let baseDirectory: URL
    private let dateFormatter: ISO8601DateFormatter
    private let fileManager = FileManager.default

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseDirectory = appSupport.appendingPathComponent("DeskMate/local-history", isDirectory: true)
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    // MARK: - 公共 API

    /// 保存一个快照。若内容与最新快照相同则跳过，避免重复。
    func saveSnapshot(
        workspace: String,
        filePath: String,
        content: String,
        source: LocalHistorySource
    ) {
        let standardizedWorkspace = (workspace as NSString).standardizingPath
        let standardizedFilePath = (filePath as NSString).standardizingPath

        guard let relativePath = Self.relativePath(for: standardizedFilePath, workspace: standardizedWorkspace) else {
            DMLogger.log("LocalHistoryStore: 文件不在工作区内，跳过快照 \(filePath)", name: "LocalHistoryStore")
            return
        }

        // 去重：与最新快照内容相同则跳过
        if let latest = try? latestSnapshotInternal(workspace: standardizedWorkspace, filePath: relativePath),
           latest.content == content {
            return
        }

        let snapshot = LocalHistorySnapshot(
            id: UUID(),
            filePath: relativePath,
            workspacePath: standardizedWorkspace,
            timestamp: Date(),
            content: content,
            source: source
        )

        do {
            let dir = snapshotDirectory(workspace: standardizedWorkspace, filePath: relativePath)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("\(filenameTimestamp(for: snapshot.timestamp)).json")
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            DMLogger.error("LocalHistoryStore: 保存快照失败 \(filePath): \(error.localizedDescription)", name: "LocalHistoryStore")
        }
    }

    /// 获取某文件的最新快照。
    func latestSnapshot(workspace: String, filePath: String) -> LocalHistorySnapshot? {
        let standardizedWorkspace = (workspace as NSString).standardizingPath
        let standardizedFilePath = (filePath as NSString).standardizingPath
        guard let relativePath = Self.relativePath(for: standardizedFilePath, workspace: standardizedWorkspace) else {
            return nil
        }
        return try? latestSnapshotInternal(workspace: standardizedWorkspace, filePath: relativePath)
    }

    /// 列出某文件的所有快照，按时间从新到旧排序。
    func listSnapshots(workspace: String, filePath: String) -> [LocalHistorySnapshot] {
        let standardizedWorkspace = (workspace as NSString).standardizingPath
        let standardizedFilePath = (filePath as NSString).standardizingPath
        guard let relativePath = Self.relativePath(for: standardizedFilePath, workspace: standardizedWorkspace) else {
            return []
        }
        let dir = snapshotDirectory(workspace: standardizedWorkspace, filePath: relativePath)
        return listSnapshots(in: dir)
    }

    /// 恢复指定 id 的快照内容。
    func restoreSnapshot(id: UUID) -> String? {
        guard let url = findSnapshotFile(id: id) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(LocalHistorySnapshot.self, from: data) else {
            return nil
        }
        return snapshot.content
    }

    /// 删除指定 id 的快照。
    func deleteSnapshot(id: UUID) {
        guard let url = findSnapshotFile(id: id) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// 清理过期快照。默认单文件保留 50 个、30 天内。
    func cleanup(keepingMax: Int = 50, maxAge: TimeInterval = 30 * 24 * 60 * 60) {
        let cutoff = Date().addingTimeInterval(-maxAge)

        guard let workspaceDirs = try? fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for workspaceDir in workspaceDirs {
            cleanupDirectory(workspaceDir, keepingMax: keepingMax, cutoff: cutoff)
        }
    }

    // MARK: - 内部方法

    private func latestSnapshotInternal(workspace: String, filePath: String) throws -> LocalHistorySnapshot? {
        let dir = snapshotDirectory(workspace: workspace, filePath: filePath)
        return listSnapshots(in: dir).first
    }

    private func listSnapshots(in directory: URL) -> [LocalHistorySnapshot] {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        let snapshots: [LocalHistorySnapshot] = files.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(LocalHistorySnapshot.self, from: data) else {
                return nil
            }
            return snapshot
        }

        return snapshots.sorted { $0.timestamp > $1.timestamp }
    }

    private func findSnapshotFile(id: UUID) -> URL? {
        guard let workspaceDirs = try? fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil) else {
            return nil
        }

        for workspaceDir in workspaceDirs {
            if let url = findSnapshotFile(id: id, in: workspaceDir) {
                return url
            }
        }
        return nil
    }

    private func findSnapshotFile(id: UUID, in directory: URL) -> URL? {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }

        for url in contents {
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                if let found = findSnapshotFile(id: id, in: url) { return found }
            } else if url.pathExtension == "json" {
                guard let data = try? Data(contentsOf: url),
                      let snapshot = try? JSONDecoder().decode(LocalHistorySnapshot.self, from: data),
                      snapshot.id == id else {
                    continue
                }
                return url
            }
        }
        return nil
    }

    private func cleanupDirectory(_ directory: URL, keepingMax: Int, cutoff: Date) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }

        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        var snapshotFiles: [URL] = []
        var subdirectories: [URL] = []

        for url in contents {
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                subdirectories.append(url)
            } else if url.pathExtension == "json" {
                snapshotFiles.append(url)
            }
        }

        // 递归清理子目录
        for subdir in subdirectories {
            cleanupDirectory(subdir, keepingMax: keepingMax, cutoff: cutoff)
        }

        // 删除过期文件
        let datedFiles = snapshotFiles.compactMap { url -> (url: URL, date: Date)? in
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(LocalHistorySnapshot.self, from: data) else {
                return nil
            }
            return (url, snapshot.timestamp)
        }.sorted { $0.date > $1.date }

        for (index, item) in datedFiles.enumerated() {
            if index >= keepingMax || item.date < cutoff {
                try? fileManager.removeItem(at: item.url)
            }
        }

        // 若目录已空且不是 workspace 根，删除目录
        if directory != baseDirectory {
            if let remaining = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
               remaining.isEmpty {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    private func snapshotDirectory(workspace: String, filePath: String) -> URL {
        let hash = Self.workspaceHash(workspace)
        return baseDirectory
            .appendingPathComponent(hash, isDirectory: true)
            .appendingPathComponent(filePath, isDirectory: true)
    }

    private func filenameTimestamp(for date: Date) -> String {
        return dateFormatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    // MARK: - 静态辅助

    private static func workspaceHash(_ workspace: String) -> String {
        let data = Data(workspace.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16).map(String.init).joined()
    }

    private static func relativePath(for filePath: String, workspace: String) -> String? {
        guard filePath.hasPrefix(workspace + "/") else { return nil }
        return String(filePath.dropFirst(workspace.count + 1))
    }
}

// MARK: - 数据模型

struct LocalHistorySnapshot: Codable, Identifiable {
    let id: UUID
    let filePath: String
    let workspacePath: String
    let timestamp: Date
    let content: String
    let source: LocalHistorySource
}

enum LocalHistorySource: String, Codable {
    case diskOpen
    case save
    case diffApply
    case periodic
}
