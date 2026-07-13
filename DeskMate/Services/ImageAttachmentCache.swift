import Foundation

/// 本地缓存 AI 聊天消息中的图片附件，按后端消息 ID 索引。
///
/// Hermes 后端在历史消息中只保留 `[screenshot]` 等占位文本，不保存图片数据。
/// 该服务在本地维护 `sessionId -> [messageId: [ChatImageAttachment]]` 映射，
/// 图片文件本身仍由 `ImageAttachmentManager` 保存到 `~/.hermes/images/`。
final class ImageAttachmentCache {
    static let shared = ImageAttachmentCache()

    /// 索引文件路径：`~/.hermes/image_attachment_index.json`。
    private let indexURL: URL
    private let lock = NSLock()

    private var index: ImageAttachmentIndex

    private init() {
        let home = AppConstants.resolveHermesHome()
        let url = URL(fileURLWithPath: home).appendingPathComponent("image_attachment_index.json")
        self.indexURL = url
        self.index = Self.loadIndex(from: url)
    }

    // MARK: - Public

    /// 保存某条后端消息对应的图片附件列表。
    func saveAttachments(
        _ attachments: [ChatImageAttachment],
        sessionId: String,
        messageId: String
    ) {
        guard !attachments.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        index.entries[sessionId, default: [:]][messageId] = attachments
        persist()
        DMLogger.log(
            "ImageAttachmentCache saved: sessionId=\(sessionId) messageId=\(messageId) count=\(attachments.count)",
            name: "ImageAttachmentCache"
        )
    }

    /// 读取某条后端消息对应的图片附件列表。
    func attachments(forSessionId sessionId: String, messageId: String) -> [ChatImageAttachment] {
        lock.lock()
        defer { lock.unlock() }
        let result = index.entries[sessionId]?[messageId] ?? []
        DMLogger.log(
            "ImageAttachmentCache lookup: sessionId=\(sessionId) messageId=\(messageId) hit=\(!result.isEmpty) count=\(result.count)",
            name: "ImageAttachmentCache"
        )
        return result
    }

    /// 删除整个 session 的图片附件索引。
    func deleteAttachments(forSessionId sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard index.entries[sessionId] != nil else { return }
        index.entries.removeValue(forKey: sessionId)
        persist()
        DMLogger.log(
            "ImageAttachmentCache deleted session: \(sessionId)",
            name: "ImageAttachmentCache"
        )
    }

    // MARK: - Private

    private func persist() {
        do {
            let parent = indexURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                try FileManager.default.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true
                )
            }
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL, options: .atomic)
            DMLogger.log(
                "ImageAttachmentCache persisted: \(indexURL.path) entries=\(index.entries.count)",
                name: "ImageAttachmentCache"
            )
        } catch {
            DMLogger.error(
                "ImageAttachmentCache persist failed: \(error.localizedDescription)",
                name: "ImageAttachmentCache"
            )
        }
    }

    private static func loadIndex(from url: URL) -> ImageAttachmentIndex {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ImageAttachmentIndex.self, from: data) else {
            return ImageAttachmentIndex()
        }
        return decoded
    }
}

/// 索引文件顶层结构。
private struct ImageAttachmentIndex: Codable {
    /// `sessionId -> messageId -> attachments`
    var entries: [String: [String: [ChatImageAttachment]]] = [:]
}
