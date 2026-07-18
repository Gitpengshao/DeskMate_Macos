import Foundation
import Combine

/// Gateway 连接状态管理 — 供 Main 控制台头部徽标实时反映 `/health` 探测结果。
///
/// 轻量 `@MainActor ObservableObject` 单例，只读包装 `HermesGatewayService.isHealthy()`。
/// 不改造 `HermesGatewayService`（它持有 Process + 异步 start/stop），避免 ObservableObject 化风险。
@MainActor
final class GatewayConnectionManager: ObservableObject {

    static let shared = GatewayConnectionManager()

    enum Status: Equatable {
        case checking
        case connected
        case disconnected
    }

    @Published private(set) var status: Status = .checking

    private var timer: Timer?

    private init() {}

    /// 立即探测一次 `/health` 并更新状态。
    /// 健康探测本身在后台线程执行，避免在 MainActor 上 await 网络超时，
    /// 从而减少与 SwiftUI 视图更新周期冲突导致的 "Modifying state during view update"。
    func refresh() async {
        let healthy = await Task.detached(priority: .utility) {
            await HermesGatewayService.shared.isHealthy()
        }.value
        status = healthy ? .connected : .disconnected
    }

    /// 启动周期性健康探测（每 10s 一次）。重复调用安全。
    func startMonitoring() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 停止周期性探测。
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
