import SwiftUI

/// 聊天头部 — 整体黑白风格设计。
struct ChatHeader: View {
    let sessionTitle: String?
    let sessionId: String?
    let sidebarVisible: Bool
    let isDark: Bool
    let onToggleSidebar: () -> Void
    /// 当前默认模型（从 `~/.hermes/config.yaml` 读取）。
    /// `nil` 表示尚未加载或未配置。
    let currentModel: CurrentModelInfo?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleSidebar) {
                Image(systemName: sidebarVisible ? "sidebar.squares.left" : "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textSecond)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Palette.bgPanel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Palette.border, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .onHover { h in
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(sessionTitle ?? "新建对话")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                if let sid = sessionId {
                    let display = sid.count > 12 ? String(sid.prefix(12)) + "..." : sid
                    Text("ID: \(display)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Palette.textTertiary)
                }
            }

            Spacer()

            // 模型指示器 — 数据来自 ~/.hermes/config.yaml 的 model.default
            modelIndicator
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.bgPanel)
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    /// 头部右侧的模型徽标。
    ///
    /// 显示优先级：
    /// 1. 若 `currentModel` 已加载且 provider 非空 → "provider · model"
    /// 2. 若 `currentModel` 仅 displayName → 直接显示
    /// 3. 未加载（nil）→ 显示 "未配置" 占位（保持徽标宽度稳定，避免抖动）
    @ViewBuilder
    private var modelIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Palette.textPrimary)
                .frame(width: 5, height: 5)
            Text(modelIndicatorText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textSecond)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Palette.bgPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Palette.border, lineWidth: 1)
                )
        )
    }

    private var modelIndicatorText: String {
        guard let m = currentModel else { return "未配置" }
        if m.provider.isEmpty { return m.displayName }
        return "\(m.provider) · \(m.displayName)"
    }
}

// MARK: - Palette

private enum Palette {
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
}
