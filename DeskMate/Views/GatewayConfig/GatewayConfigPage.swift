import SwiftUI

/// 消息网关配置页 — 极简连接入口。
///
/// 只保留：状态、启动/停止、扫码配置、终端兜底。
struct GatewayConfigPage: View {
    @StateObject private var viewModel = GatewayConfigViewModel()

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
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(GCPalette.textPrimary)
                Text("消息网关")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(GCPalette.textPrimary)
            }

            Spacer()

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
        case .connected:    return "已连接"
        case .disconnected: return "未连接"
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
        VStack(spacing: 20) {
            Spacer()

            statusCard
            actionCard

            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status card

    private var statusCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                StatusDot(color: gatewayStatusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gatewayStatusLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(GCPalette.textPrimary)
                    Text("端口 \(AppConstants.defaultGatewayPort)")
                        .font(.system(size: 11))
                        .foregroundColor(GCPalette.textTertiary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                PrimaryButton(
                    title: viewModel.isGatewayBusy ? "处理中..." : "启动",
                    icon: "play.fill"
                ) {
                    viewModel.startGateway()
                }
                .disabled(viewModel.isGatewayBusy || viewModel.gatewayStatus == .connected)

                SecondaryButton(
                    title: "停止",
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
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(GCPalette.bgPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GCPalette.border, lineWidth: 1)
                )
        )
    }

    // MARK: - Action card

    private var actionCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "qrcode")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(GCPalette.textPrimary)
                Text("扫码连接")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GCPalette.textPrimary)
                Text("运行 hermes gateway setup 完成扫码与连接")
                    .font(.system(size: 11))
                    .foregroundColor(GCPalette.textTertiary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                PrimaryButton(
                    title: "开始扫码配置",
                    icon: "qrcode"
                ) {
                    viewModel.startSetup()
                }
                .frame(maxWidth: .infinity)

                SecondaryButton(
                    title: "在终端打开",
                    icon: "terminal"
                ) {
                    viewModel.openSetupInTerminal()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(GCPalette.bgPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
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
            .frame(width: 720, height: 520)
    }
}
#endif
