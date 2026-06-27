import SwiftUI

/// Content area — 整体黑白风格设计。
struct MainContentArea: View {
    let activeNavId: String
    let viewModel: MainViewModel
    var isDark: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            pageContent
        }
        .background(Palette.bgBase)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Text(viewModel.itemLabel(activeNavId))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .tracking(0.1)

            Spacer()

            HStack(spacing: 8) {
                PillBadge(
                    icon: Circle()
                        .fill(Palette.textPrimary)
                        .frame(width: 6, height: 6)
                        .opacity(0.95),
                    label: gatewayStatusLabel
                )
                PillBadge(label: "Lv.12 花花")
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 49)
        .background(Palette.bgPanel)
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var gatewayStatusLabel: String { "Gateway 已连接" }

    // MARK: - Page Content

    @ViewBuilder
    private var pageContent: some View {
        Group {
            switch activeNavId {
            case "ai-chat":
                AiChatPage(isDark: isDark)
            case "agent":             AgentPage()
            case "memory-management": MemoryManagementPage()
            case "task-board":        TaskBoardPage()
            case "model-config":      ModelConfigPage()
            case "skill-management":  SkillManagementPage()
            case "settings":          placeholderPage(title: "设置", icon: "gearshape")
            default:                  placeholderPage(title: viewModel.itemLabel(activeNavId), icon: "square.grid.2x2")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func placeholderPage(title: String, icon: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Palette.border, lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(Palette.textSecond)
            }
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Palette.textPrimary)
            Text("此页面正在开发中…")
                .font(.system(size: 12))
                .foregroundColor(Palette.textTertiary)
        }
    }
}

// MARK: - Palette (Monochrome)

private enum Palette {
    static let bgBase      = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let bgElevated  = Color(red: 0.078, green: 0.078, blue: 0.078)
    static let bgHover     = Color(red: 0.110, green: 0.110, blue: 0.110)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
    static let inverse     = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let inverseInk  = Color(red: 0.000, green: 0.000, blue: 0.000)
}

// MARK: - Pill Badge

private struct PillBadge: View {
    let icon: AnyView?
    let label: String

    init(label: String) {
        self.icon = nil
        self.label = label
    }

    init(icon: some View, label: String) {
        self.icon = AnyView(icon)
        self.label = label
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                icon
            }
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
        }
        .foregroundColor(Palette.textSecond)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Palette.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Palette.border, lineWidth: 1)
                )
        )
    }
}
