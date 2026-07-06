import SwiftUI
import Combine

/// 网关配置页 ViewModel。
///
/// 管理：
/// - 网关状态监听（绑定 `GatewayConnectionManager.shared`）
/// - 交互式进程（扫码 setup）的输出与控制
/// - 启动 / 停止网关
@MainActor
final class GatewayConfigViewModel: ObservableObject {

    @Published var errorMessage: String?

    // MARK: - Gateway status

    @Published var gatewayStatus: GatewayConnectionManager.Status = .checking
    @Published var isGatewayBusy: Bool = false

    // MARK: - Interactive console

    @Published var interactiveOutput: String = ""
    @Published var isInteractiveRunning: Bool = false
    @Published var interactiveTitle: String = ""
    @Published var lastExitCode: Int32?

    private var currentRunner: InteractiveProcessRunner?
    private var connectionCancellable: AnyCancellable?

    private let service = MessagingConfigService.shared

    init() {
        // 监听 GatewayConnectionManager 状态
        connectionCancellable = GatewayConnectionManager.shared.$status
            .receive(on: DispatchQueue.main)
            .assign(to: \.gatewayStatus, on: self)
    }

    // MARK: - Gateway lifecycle

    func startGateway() {
        guard !isGatewayBusy else { return }
        isGatewayBusy = true
        Task {
            let ok = await service.startGateway()
            self.isGatewayBusy = false
            if !ok {
                self.errorMessage = "网关启动失败，请检查 Hermes 是否已安装。"
            }
            await GatewayConnectionManager.shared.refresh()
        }
    }

    func stopGateway() {
        guard !isGatewayBusy else { return }
        isGatewayBusy = true
        Task {
            await service.stopGateway()
            self.isGatewayBusy = false
            await GatewayConnectionManager.shared.refresh()
        }
    }

    // MARK: - Interactive: hermes gateway setup

    /// 启动 `hermes gateway setup` 交互式进程，输出写入 `interactiveOutput`。
    func startSetup() {
        guard !isInteractiveRunning else { return }
        interactiveOutput = ""
        lastExitCode = nil
        interactiveTitle = "hermes gateway setup"
        isInteractiveRunning = true

        let runner = service.startGatewaySetup(
            onOutput: { [weak self] snapshot in
                self?.interactiveOutput = snapshot
            },
            onExit: { [weak self] code in
                guard let self = self else { return }
                self.lastExitCode = code
                self.isInteractiveRunning = false
            }
        )
        currentRunner = runner
    }

    /// 向交互式进程 stdin 发送一行输入。
    func sendInput(_ text: String) {
        currentRunner?.send(text)
    }

    /// 取消当前交互式进程（终止 setup，或关闭安装输出 sheet）。
    func cancelInteractive() {
        currentRunner?.terminate()
        currentRunner = nil
        isInteractiveRunning = false
    }

    /// 关闭输出 sheet（不终止进程，仅隐藏 UI）。
    func dismissInteractive() {
        // 如果是交互式 setup 进程，关闭 sheet 时也终止它（避免后台残留）
        currentRunner?.terminate()
        currentRunner = nil
        isInteractiveRunning = false
    }

    // MARK: - Terminal fallback

    /// 在外部 Terminal.app 中打开 `hermes gateway setup`（兜底方案）。
    func openSetupInTerminal() {
        let cmd = "cd \"\(service.hermesHomeForTerminal)\" && \"\(service.pythonPathForTerminal)\" -m hermes_cli.main gateway setup"
        InteractiveProcessRunner.openInTerminal(command: cmd)
    }
}
