import SwiftUI

/// Diff 单行视图：包含双行号 gutter、内容高亮与行级接受/拒绝按钮。
struct DiffLineRowView: View {
    let line: DiffLine
    let action: DiffAction
    let onAccept: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false

    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let lineHeight: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            // 旧行号 gutter
            lineNumberCell(value: line.oldLineNumber, width: 48, alignment: .trailing)

            Divider().background(Palette.border)

            // 新行号 gutter
            lineNumberCell(value: line.newLineNumber, width: 48, alignment: .trailing)

            Divider().background(Palette.border)

            // diff 标记（+ / -）
            Text(diffMarker)
                .font(Font(font))
                .foregroundColor(markerColor)
                .frame(width: 16, alignment: .center)
                .background(rowBackground)

            // 内容
            Text(line.text)
                .font(Font(font))
                .foregroundColor(textColor)
                .lineSpacing(0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground)

            // 行级操作按钮（hover 或已做决定时显示）
            if isHovered || action != .default {
                HStack(spacing: 6) {
                    actionButton(
                        icon: "checkmark",
                        color: DiffPalette.addedForeground,
                        isActive: action == .accepted,
                        action: onAccept
                    )
                    .help("接受该行")

                    actionButton(
                        icon: "xmark",
                        color: DiffPalette.deletedForeground,
                        isActive: action == .rejected,
                        action: onReject
                    )
                    .help("拒绝该行")
                }
                .padding(.horizontal, 6)
                .background(Palette.bgBase)
                .transition(.opacity)
            }
        }
        .frame(height: lineHeight)
        .background(Palette.bgBase)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private func actionButton(
        icon: String,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isActive ? Palette.bgBase : color)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? color : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 子视图

    private func lineNumberCell(value: Int?, width: CGFloat, alignment: Alignment) -> some View {
        Text(value.map { "\($0)" } ?? "")
            .font(Font(NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)))
            .foregroundColor(Palette.textTertiary)
            .frame(width: width, height: lineHeight, alignment: alignment)
            .padding(.horizontal, 4)
            .background(Palette.bgPanel)
    }

    // MARK: - 样式计算

    private var diffMarker: String {
        switch line.kind {
        case .added: return "+"
        case .deleted: return "-"
        default: return ""
        }
    }

    private var rowBackground: Color {
        switch line.kind {
        case .added:
            return action == .rejected ? Palette.bgBase : DiffPalette.addedBackground
        case .deleted:
            return action == .accepted ? Palette.bgBase : DiffPalette.deletedBackground
        default:
            return Palette.bgBase
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .added: return DiffPalette.addedForeground
        case .deleted: return DiffPalette.deletedForeground
        default: return Palette.textTertiary
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .added:
            return action == .rejected ? Palette.textTertiary : DiffPalette.addedForeground
        case .deleted:
            return action == .accepted ? Palette.textTertiary : DiffPalette.deletedForeground
        default:
            return Palette.textPrimary
        }
    }
}

// MARK: - Palette

private enum Palette {
    static let bgBase      = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let bgElevated  = Color(red: 0.078, green: 0.078, blue: 0.078)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
}
