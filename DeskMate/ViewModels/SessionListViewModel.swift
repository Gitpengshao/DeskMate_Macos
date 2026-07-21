import Foundation
import SwiftUI
import Combine

/// 会话列表 ViewModel — 对齐 Flutter `SessionListViewModel`（Riverpod Notifier）。
@MainActor
final class SessionListViewModel: ObservableObject {

    /// 当前侧边栏状态（会话列表、加载/错误标记）。
    /// 使用默认值并在声明处初始化，避免 `init` 赋值触发 `objectWillChange`，
    /// 从而减少 `@StateObject` 创建时的 "Modifying state during view update" 警告。
    @Published var state: SessionStateModel = SessionStateModel()

    private let apiService: SessionApiService

    init(gateway: GatewayClient? = nil, profile: String? = nil) {
        // 在 @MainActor 隔离的 init 体内构造默认值，
        // 避免在默认参数（nonisolated 上下文）中调用 main actor-isolated 初始化器。
        // 使用 GatewayClient.shared 以便 HermesGatewayService 启动后注入的 apiKey 生效。
        let resolvedGateway = gateway ?? GatewayClient.shared
        self.apiService = SessionApiService(client: resolvedGateway, profile: profile)
    }

    /// 拉取全部会话 — 对齐 Flutter `loadSessions`。
    ///
    /// 侧边栏标题优先使用 `title`，否则使用后端返回的 `preview`（第一条用户消息）。
    func loadSessions() {
        NSLog("[SessionListVM] loadSessions: 被调用，isLoading=\(state.isLoading)")
        guard !state.isLoading else { return }

        // 把状态修改推到下一帧，避免在 body 评估期间直接修改 @Published。
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.state.isLoading = true
            self.state.errorMessage = nil

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

            DMLogger.log(
                "SessionListVM: loaded \(sessions.count) sessions",
                name: "SessionListVM"
            )
            self.state.sessions = sessions
            self.state.isLoading = false
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
            Task { @MainActor [weak self] in
                self?.state.sessions.removeAll { $0.id == id }
            }
        }
    }

    /// 重新拉取会话 — 对齐 Flutter `refresh`。
    func refresh() {
        loadSessions()
    }
}
