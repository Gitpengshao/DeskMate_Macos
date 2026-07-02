import SwiftUI

/// 消息网关配置页 — 把 `hermes gateway setup` / `hermes gateway` / 编辑 `.env` 等
/// 终端命令全部映射为可视化操作。
///
/// 布局：
/// 1. 页面头部 — 标题 + 网关状态徽章
/// 2. 网关状态卡 — 状态/端口 + 启动/停止按钮
/// 3. TabView — 飞书/Lark、微信 两个配置表单
///
/// 官方文档：
/// - 飞书/Lark: https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/messaging/feishu
/// - 微信:     https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/messaging/weixin
struct GatewayConfigPage: View {
    @StateObject private var viewModel = GatewayConfigViewModel()
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            GCPalette.bgBase.ignoresSafeArea()

            VStack(spacing: 0) {
                pageHeader
                Divider().background(GCPalette.border)
                content
            }
        }
        .preferredColorScheme(.dark)
        .task {
            viewModel.loadAll()
            GatewayConnectionManager.shared.startMonitoring()
        }
        .onDisappear {
            GatewayConnectionManager.shared.stopMonitoring()
        }
        .sheet(isPresented: $viewModel.isInteractiveRunning) {
            InteractiveConsoleSheet(viewModel: viewModel)
        }
        .alert("出错了", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("好") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(GCPalette.textPrimary)
                    Text("消息网关配置")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(GCPalette.textPrimary)
                }
                Text("把 Hermes 终端命令变成可视化操作 — 配置微信、飞书 / Lark 连接")
                    .font(.system(size: 12))
                    .foregroundColor(GCPalette.textSecond)
            }

            Spacer()

            // 网关状态徽章
            HStack(spacing: 6) {
                StatusDot(color: gatewayStatusColor)
                Text(gatewayStatusLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(GCPalette.textSecond)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(GCPalette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(GCPalette.border, lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 24)
        .frame(height: 60)
        .background(GCPalette.bgPanel)
    }

    private var gatewayStatusLabel: String {
        switch viewModel.gatewayStatus {
        case .checking:     return "检测中"
        case .connected:    return "网关已连接"
        case .disconnected: return "网关未连接"
        }
    }

    private var gatewayStatusColor: Color {
        switch viewModel.gatewayStatus {
        case .checking:     return GCPalette.textTertiary
        case .connected:    return GCPalette.good
        case .disconnected: return GCPalette.bad
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            gatewayStatusBar
                .padding(.horizontal, 24)
                .padding(.top, 16)

            // Tab 切换
            TabView(selection: $selectedTab) {
                FeishuConfigSection(viewModel: viewModel)
                    .tag(0)
                    .tabItem {
                        Label("飞书 / Lark", systemImage: "message.fill")
                    }
                WeixinConfigSection(viewModel: viewModel)
                    .tag(1)
                    .tabItem {
                        Label("微信", systemImage: "phone.fill")
                    }
            }
            .tabViewStyle(.automatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Gateway status bar

    private var gatewayStatusBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    StatusDot(color: gatewayStatusColor)
                    Text(gatewayStatusLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(GCPalette.textPrimary)
                }
                Text("端口 \(AppConstants.defaultGatewayPort) · Hermes Gateway")
                    .font(.system(size: 11))
                    .foregroundColor(GCPalette.textTertiary)
            }

            Spacer()

            HStack(spacing: 10) {
                PrimaryButton(
                    title: viewModel.isGatewayBusy ? "处理中..." : "启动网关",
                    icon: "play.fill"
                ) {
                    viewModel.startGateway()
                }
                .disabled(viewModel.isGatewayBusy || viewModel.gatewayStatus == .connected)

                SecondaryButton(
                    title: "停止网关",
                    icon: "stop.fill"
                ) {
                    viewModel.stopGateway()
                }
                .disabled(viewModel.isGatewayBusy || viewModel.gatewayStatus != .connected)

                SecondaryButton(
                    title: "重启",
                    icon: "arrow.clockwise"
                ) {
                    viewModel.stopGateway()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        viewModel.startGateway()
                    }
                }
                .disabled(viewModel.isGatewayBusy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(GCPalette.bgPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GCPalette.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#if DEBUG
struct GatewayConfigPage_Previews: PreviewProvider {
    static var previews: some View {
        GatewayConfigPage()
            .frame(width: 900, height: 640)
    }
}
#endif
