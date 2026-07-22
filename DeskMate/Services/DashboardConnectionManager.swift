import Foundation
import Combine

/// Dashboard 连接状态管理 — 供 Main 控制台头部徽标实时反映 Dashboard 健康状态。
///
/// 轻量 `@MainActor ObservableObject` 单例，只读包装 `HermesDashboardService.isHealthy()`。
@MainActor
final class DashboardConnectionManager: ObservableObject {

    static let shared = DashboardConnectionManager()

    enum Status: Equatable {
        case checking
        case connected
        case disconnected
    }

    @Published private(set) var status: Status = .checking

    private var timer: Timer?

    private init() {}

    /// 立即探测一次 Dashboard 健康状态并更新状态。
    func refresh() async {
        let healthy = await Task.detached(priority: .utility) {
            await HermesDashboardService.shared.isHealthy()
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
