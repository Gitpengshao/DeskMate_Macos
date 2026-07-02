import SwiftUI
import Combine

/// 网关配置页 ViewModel。
///
/// 管理：
/// - 飞书 / 微信配置的加载与保存
/// - 网关状态监听（绑定 `GatewayConnectionManager.shared`）
/// - 交互式进程（扫码 setup / 依赖安装）的输出与控制
@MainActor
final class GatewayConfigViewModel: ObservableObject {

    // MARK: - Config state

    @Published var feishuConfig: FeishuConfig = .init()
    @Published var weixinConfig: WeixinConfig = .init()

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var feishuSavedAt: Date?
    @Published var weixinSavedAt: Date?

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

    // MARK: - Load

    /// 加载飞书 + 微信配置（从 `.env`）。
    func loadAll() {
        isLoading = true
        errorMessage = nil
        Task.detached(priority: .userInitiated) { [service] in
            let feishu = service.loadFeishuConfig()
            let weixin = service.loadWeixinConfig()
            await MainActor.run {
                self.feishuConfig = feishu
                self.weixinConfig = weixin
                self.isLoading = false
            }
        }
    }

    /// 仅重新加载微信配置（扫码完成后调用，读取自动写入的 token）。
    func reloadWeixinConfig() {
        Task.detached(priority: .userInitiated) { [service] in
            let weixin = service.loadWeixinConfig()
            await MainActor.run {
                self.weixinConfig = weixin
            }
        }
    }

    // MARK: - Save

    func saveFeishu() {
        let cfg = feishuConfig
        Task.detached(priority: .userInitiated) { [service] in
            service.saveFeishuConfig(cfg)
            await MainActor.run {
                self.feishuSavedAt = Date()
            }
        }
    }

    func saveWeixin() {
        let cfg = weixinConfig
        Task.detached(priority: .userInitiated) { [service] in
            service.saveWeixinConfig(cfg)
            await MainActor.run {
                self.weixinSavedAt = Date()
            }
        }
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
                // setup 完成后重新读取配置（扫码可能已写入凭据）
                self.loadAll()
            }
        )
        currentRunner = runner
    }

    /// 安装微信依赖 `aiohttp` + `cryptography`。
    func installWeixinDeps() {
        guard !isInteractiveRunning else { return }
        interactiveOutput = "正在安装微信依赖 aiohttp + cryptography ...\n"
        lastExitCode = nil
        interactiveTitle = "安装微信依赖"
        isInteractiveRunning = true

        // 依赖安装是非交互的，但复用同一个 sheet 展示输出。
        service.installWeixinDeps(
            onOutput: { [weak self] output in
                guard let self = self else { return }
                // StreamingProcessRunner 推送的是尾部若干行，这里追加显示
                self.interactiveOutput += output + "\n"
            },
            onExit: { [weak self] code in
                guard let self = self else { return }
                self.lastExitCode = code
                self.interactiveOutput += "\n[进程退出，code=\(code)]\n"
                // 不自动关闭 sheet，让用户看到结果；用户手动点「关闭」
            }
        )
    }

    /// 重装 messaging 扩展。
    func reinstallMessagingExt() {
        guard !isInteractiveRunning else { return }
        interactiveOutput = "正在重装 messaging 扩展 ...\n"
        lastExitCode = nil
        interactiveTitle = "重装 messaging 扩展"
        isInteractiveRunning = true

        service.reinstallMessagingExt(
            onOutput: { [weak self] output in
                guard let self = self else { return }
                self.interactiveOutput += output + "\n"
            },
            onExit: { [weak self] code in
                guard let self = self else { return }
                self.lastExitCode = code
                self.interactiveOutput += "\n[进程退出，code=\(code)]\n"
            }
        )
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
