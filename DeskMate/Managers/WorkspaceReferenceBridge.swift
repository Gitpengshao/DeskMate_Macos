import Foundation
import Combine

/// 一条"工作区 → AI 对话"的待加入引用。
///
/// 每次 `enqueue` 都会生成新的 `id`，确保相同路径重复入队时仍能触发
/// `@Published` 通知（避免 SwiftUI Combine 因值相等而吞掉变更）。
struct PendingWorkspaceReference: Equatable {
    let path: String
    let isDirectory: Bool
    let id: UUID

    init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
        self.id = UUID()
    }
}

/// 跨窗口引用桥接器 — 工作区浏览器向 AI 对话页"投递"待加入的文件/目录路径。
///
/// 使用场景：`WorkspaceExplorerView` 位于独立 `NSWindow` 中，没有直接引用
/// `AiChatViewModel`；通过该单例发布请求，主窗口中常驻的 `AiChatPage` 订阅
/// 后调用 `chatVM.addReference(...)`。
@MainActor
final class WorkspaceReferenceBridge: ObservableObject {
    static let shared = WorkspaceReferenceBridge()

    /// 最近一次入队的待加入引用 — 消费后由消费者调用 `consume()` 清空。
    @Published private(set) var pendingReference: PendingWorkspaceReference?

    private init() {}

    /// 推入一条新的待加入引用。每次都生成新 `id`，确保 SwiftUI 能感知变更。
    func enqueue(path: String, isDirectory: Bool) {
        pendingReference = PendingWorkspaceReference(path: path, isDirectory: isDirectory)
    }

    /// 消费当前待加入引用 — 通常由 `AiChatPage` 在处理完毕后调用，
    /// 防止下次重复入队相同路径时被 Combine 判等而忽略。
    func consume() {
        pendingReference = nil
    }
}
