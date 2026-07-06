import SwiftUI

/// Sidebar view — 整体黑白风格设计。
struct MainSidebar: View {
    @ObservedObject var viewModel: MainViewModel
    var isDark: Bool

    private let sidebarWidth: CGFloat = 223

    // MARK: - Monochrome Design Tokens
    private var bgColor: Color { Palette.bgPanel }
    private var borderColor: Color { Palette.border }
    private var textColor: Color { Palette.textPrimary }
    private var sectionLabelColor: Color { Palette.textTertiary }

    var body: some View {
        VStack(spacing: 0) {
            // Logo header
            logoHeader

            // Navigation sections (scrollable)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.groupedItems, id: \.sectionKey) { group in
                        navSection(sectionKey: group.sectionKey, items: group.items)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(width: sidebarWidth)
        .background(bgColor)
        .overlay(
            Rectangle()
                .fill(borderColor)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    // MARK: - Logo Header

    private var logoHeader: some View {
        HStack(spacing: 10) {
            Image("applogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)

            Text("DeskMate")
                .font(.system(size: 17, weight: .semibold))
                .tracking(0.2)
        }
        .foregroundColor(textColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .overlay(
            Rectangle()
                .fill(borderColor)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Nav Section

    private func navSection(sectionKey: String, items: [SidebarNavItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.sectionLabel(sectionKey))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(sectionLabelColor)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 6)

            ForEach(items) { item in
                navItemRow(item)
            }
        }
    }

    // MARK: - Nav Item Row

    private func navItemRow(_ item: SidebarNavItem) -> some View {
        NavItemRow(
            item: item,
            isActive: item.id == viewModel.model.activeNavId,
            activeLabel: viewModel.itemLabel(item.id),
            onTap: { viewModel.switchNav(item.id) }
        )
    }
}

// MARK: - Palette (Monochrome)

private enum Palette {
    static let bgBase      = Color(red: 0.000, green: 0.000, blue: 0.000)  // #000000
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)  // #0A0A0A
    static let bgElevated  = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let bgHover     = Color(red: 0.110, green: 0.110, blue: 0.110)  // #1C1C1C
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)  // #262626
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)  // #FFFFFF
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)  // #A3A3A3
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)  // #6B6B6B
    static let inverse     = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let inverseInk  = Color(red: 0.000, green: 0.000, blue: 0.000)
}

// MARK: - Nav Item Row

private struct NavItemRow: View {
    let item: SidebarNavItem
    let isActive: Bool
    let activeLabel: String
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    private var fillColor: Color {
        if isActive { return Palette.inverse }        // 选中：白底
        if isHovered { return Palette.bgHover }       // 悬停：暗灰
        return .clear
    }
    private var rowTextColor: Color {
        isActive ? Palette.inverseInk : (isHovered ? Palette.textPrimary : Palette.textSecond)
    }
    private var rowWeight: Font.Weight { isActive ? .semibold : .medium }
    private var iconOpacity: Double { isActive ? 1.0 : 0.85 }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: item.iconName)
                    .font(.system(size: 13.5, weight: .medium))
                    .opacity(iconOpacity)

                Text(activeLabel)
                    .font(.system(size: 13, weight: rowWeight))

                Spacer()
            }
            .foregroundColor(rowTextColor)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fillColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
