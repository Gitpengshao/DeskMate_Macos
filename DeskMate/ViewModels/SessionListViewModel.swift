import Foundation
import SwiftUI
import Combine

/// 会话列表 ViewModel — 对齐 Flutter `SessionListViewModel`（Riverpod Notifier）。
@MainActor
final class SessionListViewModel: ObservableObject {

    @Published var state: SessionStateModel

    private let apiService: SessionApiService

    init(gateway: GatewayClient? = nil, profile: String? = nil) {
        // 在 @MainActor 隔离的 init 体内构造默认值，
        // 避免在默认参数（nonisolated 上下文）中调用 main actor-isolated 初始化器。
        // 使用 GatewayClient.shared 以便 HermesGatewayService 启动后注入的 apiKey 生效。
        let resolvedGateway = gateway ?? GatewayClient.shared
        self.apiService = SessionApiService(client: resolvedGateway, profile: profile)
        self.state = SessionStateModel()
    }

    /// 拉取全部会话 — 对齐 Flutter `loadSessions`。
    ///
    /// 侧边栏标题优先使用 `title`，否则使用后端返回的 `preview`（第一条用户消息）。
    func loadSessions() {
        guard !state.isLoading else { return }
        state.isLoading = true
        state.errorMessage = nil

        Task { [weak self] in
            guard let self = self else { return }
            let sessions = await self.apiService.fetchSessions()

            for session in sessions {
                DMLogger.log(
                    "SessionListVM session \(session.id): " +
                    "title=\(session.title), " +
                    "preview=\(session.preview), " +
                    "assistantPreview=\(session.assistantPreview)",
                    name: "SessionListVM"
                )
            }

            await MainActor.run {
                DMLogger.log(
                    "SessionListVM: loaded \(sessions.count) sessions",
                    name: "SessionListVM"
                )
                self.state.sessions = sessions
                self.state.isLoading = false
            }
        }
    }

    /// 更新搜索词并本地过滤 — 对齐 Flutter `updateSearch`。
    func updateSearch(_ query: String) {
        state.searchQuery = query
    }

    /// 删除会话并刷新列表 — 对齐 Flutter `deleteSession`。
    func deleteSession(_ id: String) {
        Task { [weak self] in
            guard let self = self else { return }
            _ = await self.apiService.deleteSessions([id])
            // 同步清理本地图片附件索引
            ImageAttachmentCache.shared.deleteAttachments(forSessionId: id)
            await MainActor.run {
                self.state.sessions.removeAll { $0.id == id }
            }
        }
    }

    /// 重新拉取会话 — 对齐 Flutter `refresh`。
    func refresh() {
        loadSessions()
    }
}
