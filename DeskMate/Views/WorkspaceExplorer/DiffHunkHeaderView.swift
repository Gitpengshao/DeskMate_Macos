import SwiftUI

/// Hunk 头行：显示 `@@ -a,b +c,d @@` 并提供块级接受/拒绝按钮。
struct DiffHunkHeaderView: View {
    let hunk: DiffHunk
    let action: DiffAction
    let onAccept: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(hunk.header)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DiffPalette.hunkHeaderForeground)

            Spacer()

            if isHovered || action != .default {
                HStack(spacing: 6) {
                    actionButton(
                        icon: "checkmark",
                        color: DiffPalette.addedForeground,
                        isActive: action == .accepted,
                        action: onAccept
                    )
                    .help("接受整个 Hunk")

                    actionButton(
                        icon: "xmark",
                        color: DiffPalette.deletedForeground,
                        isActive: action == .rejected,
                        action: onReject
                    )
                    .help("拒绝整个 Hunk")
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DiffPalette.hunkHeaderBackground)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
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
}

// MARK: - Palette

private enum Palette {
    static let bgBase = Color(red: 0.000, green: 0.000, blue: 0.000)
}
