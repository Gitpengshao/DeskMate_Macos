import Foundation

/// 会话 API + 本地缓存服务 — 对齐 Flutter `SessionApiService`。
///
/// macOS 版本暂不引入 SQLite 依赖，本地缓存使用 JSON 文件
/// （位于 `~/.hermes/chat_cache.json`），结构与 Flutter 的 SessionRow 一致。
final class SessionApiService {

    private let client: GatewayClient
    private let cacheURL: URL

    init(client: GatewayClient) {
        self.client = client
        let hermesHome = AppConstants.resolveHermesHome()
        let url = URL(fileURLWithPath: hermesHome)
            .appendingPathComponent("chat_cache.json")
        self.cacheURL = url
        ensureCacheFile()
    }

    /// 拉取全部会话：优先 API，失败回退到本地缓存。
    func fetchSessions() async -> [SessionRow] {
        if let json = await client.getSessions(),
           let data = json["data"] as? [[String: Any]] {
            let sessions = data.map { SessionRow(from: $0) }
            await saveCache(sessions)
            DMLogger.log(
                "Fetched \(sessions.count) sessions from API",
                name: "SessionApiService"
            )
            return sessions
        }
        // 回退到本地缓存
        let cached = loadCache()
        DMLogger.log(
            "Falling back to \(cached.count) cached sessions",
            name: "SessionApiService"
        )
        return cached
    }

    /// 删除会话（API + 本地缓存）。
    func deleteSessions(_ ids: [String]) async -> Bool {
        let ok = await client.deleteSessions(ids)
        if ok {
            removeCache(ids: ids)
        } else {
            // 即使 API 失败也清理本地缓存
            removeCache(ids: ids)
        }
        return ok
    }

    // MARK: - Cache helpers

    private func ensureCacheFile() {
        let dir = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            try? Data("[]".utf8).write(to: cacheURL)
        }
    }

    private func loadCache() -> [SessionRow] {
        guard let data = try? Data(contentsOf: cacheURL),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.map { SessionRow(from: $0) }
    }

    private func saveCache(_ sessions: [SessionRow]) async {
        let arr: [[String: Any]] = sessions.map { row in
            [
                "id": row.id,
                "title": row.title,
                "source": row.source,
                "message_count": row.messageCount,
                "model": row.model,
                "started_at": row.startedAt,
                "ended_at": row.endedAt,
                "last_active": row.lastActive,
                "preview": row.preview,
                "input_tokens": row.inputTokens,
                "output_tokens": row.outputTokens,
                "assistant_preview": row.assistantPreview
            ]
        }
        // 序列化在后台执行
        Task.detached { [cacheURL] in
            guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return }
            try? data.write(to: cacheURL)
        }
    }

    private func removeCache(ids: [String]) {
        var sessions = loadCache()
        let idSet = Set(ids)
        sessions.removeAll { idSet.contains($0.id) }
        let arr: [[String: Any]] = sessions.map { row in
            [
                "id": row.id,
                "title": row.title,
                "source": row.source,
                "message_count": row.messageCount,
                "model": row.model,
                "started_at": row.startedAt,
                "ended_at": row.endedAt,
                "last_active": row.lastActive,
                "preview": row.preview,
                "input_tokens": row.inputTokens,
                "output_tokens": row.outputTokens,
                "assistant_preview": row.assistantPreview
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: arr) {
            try? data.write(to: cacheURL)
        }
    }
}
