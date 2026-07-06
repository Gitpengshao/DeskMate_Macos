import SwiftUI
import AppKit

// MARK: - Profile Avatar

/// profile 头像 — 圆形首字母 + 边框。
struct AgentAvatar: View {
    let letter: String
    let isActive: Bool
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(AgentPalette.bgElevated)
                .frame(width: size, height: size)
            Text(letter.isEmpty ? "?" : letter)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundColor(AgentPalette.textPrimary)
        }
        .overlay(
            Circle()
                .stroke(
                    isActive ? AgentPalette.inverse : AgentPalette.border,
                    lineWidth: isActive ? 1.5 : 1
                )
        )
    }
}

// MARK: - Status Pill

/// 状态徽章 — 用于显示 Gateway 状态、distribution 标签等。
struct StatusPill: View {
    let icon: String?
    let text: String
    let color: Color
    var backgroundOpacity: Double = 0.12

    init(text: String, color: Color, icon: String? = nil, bgOpacity: Double = 0.12) {
        self.text = text
        self.color = color
        self.icon = icon
        self.backgroundOpacity = bgOpacity
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(color.opacity(backgroundOpacity))
        )
        .overlay(
            Capsule().stroke(color.opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - Profile List Row

/// 左侧智能体列表行 — 简化为头像 + 名称 + 描述/模型，悬停显示编辑/重命名/删除。
struct AgentProfileRow: View {
    let profile: AgentProfile
    let isSelected: Bool
    var onTap: () -> Void
    var onDescribe: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                AgentAvatar(
                    letter: profile.avatarLetter,
                    isActive: profile.isActive,
                    size: 32
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(profile.displayTitle)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(AgentPalette.textPrimary)
                            .lineLimit(1)
                        if profile.isDefault {
                            Text("默认")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(AgentPalette.textMuted)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(AgentPalette.bgElevated)
                                )
                                .overlay(
                                    Capsule().stroke(AgentPalette.border, lineWidth: 0.5)
                                )
                        }
                    }

                    if !profile.description.isEmpty {
                        Text(profile.description)
                            .font(.system(size: 11))
                            .foregroundColor(AgentPalette.textMuted)
                            .lineLimit(1)
                    } else if !profile.model.isEmpty {
                        Text(profile.model)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AgentPalette.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isHovered {
                    HStack(spacing: 2) {
                        if let onDescribe = onDescribe {
                            rowActionButton(icon: "text.bubble", action: onDescribe)
                        }
                        if !profile.isDefault {
                            if let onRename = onRename {
                                rowActionButton(icon: "pencil", action: onRename)
                            }
                            if let onDelete = onDelete {
                                rowActionButton(icon: "trash", action: onDelete)
                            }
                        }
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(rowFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? AgentPalette.inverse.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var rowFill: Color {
        if isSelected { return AgentPalette.inverse.opacity(0.08) }
        if isHovered { return AgentPalette.bgHover }
        return .clear
    }

    private func rowActionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AgentPalette.textMuted)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Side Panel Filter

/// 左侧筛选段：搜索框 + 计数。
struct AgentSideFilter: View {
    @ObservedObject var viewModel: AgentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(AgentPalette.textMuted)
                TextField(AgentText.search, text: Binding(
                    get: { viewModel.model.searchQuery },
                    set: { viewModel.setSearchQuery($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(AgentPalette.textPrimary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AgentPalette.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AgentPalette.border, lineWidth: 0.5)
            )

            // 计数 chip
            StatusPill(
                text: String(format: AgentText.totalCount, viewModel.model.totalCount),
                color: AgentPalette.textPrimary,
                icon: "rectangle.stack.fill"
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Toolbar

/// 顶部工具栏：刷新 / 新建智能体。
struct AgentToolbar: View {
    @ObservedObject var viewModel: AgentViewModel
    var onNewProfile: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 刷新
            ToolbarGhostButton(
                title: AgentText.refresh,
                systemImage: "arrow.clockwise",
                action: { Task { await viewModel.refresh() } }
            )

            Spacer()

            // 新建智能体
            ToolbarPrimaryButton(
                title: AgentText.newProfile,
                systemImage: "plus",
                action: onNewProfile
            )
        }
    }
}

// MARK: - Toolbar Buttons

/// 描边按钮。
struct ToolbarGhostButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(AgentPalette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? AgentPalette.bgHover : AgentPalette.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AgentPalette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// 主要按钮（实心白底）。
struct ToolbarPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(AgentPalette.inverseInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? AgentPalette.textDisabled : AgentPalette.inverse)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Detail Field Row

/// 详情面板上的字段行：`标签: 值`。
struct AgentFieldRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false
    var multiline: Bool = false
    var valueColor: Color = AgentPalette.textPrimary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(AgentPalette.textMuted)
                .frame(width: 88, alignment: .trailing)
                .padding(.top, multiline ? 1 : 3)

            if value.isEmpty {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundColor(AgentPalette.textDisabled)
            } else {
                Text(value)
                    .font(.system(
                        size: 12,
                        weight: monospaced ? .regular : .medium,
                        design: monospaced ? .monospaced : .default
                    ))
                    .foregroundColor(valueColor)
                    .lineLimit(multiline ? 5 : 1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Section Header

/// 详情面板中的段标题。
struct AgentDetailSectionHeader: View {
    let icon: String
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AgentPalette.textHeader)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(AgentPalette.textHeader)
                .textCase(.uppercase)
            Spacer()
            if let trailing = trailing { trailing }
        }
        .padding(.bottom, 6)
        .overlay(
            Rectangle()
                .fill(AgentPalette.divider)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Detail Action Button

/// 详情面板中的操作按钮（行内紧凑版本）。
struct DetailActionButton: View {
    let title: String
    let systemImage: String
    var style: DetailActionStyle = .ghost
    let action: () -> Void
    @State private var isHovered: Bool = false

    enum DetailActionStyle {
        case ghost
        case primary
        case danger
    }

    private var bgColor: Color {
        if isHovered {
            switch style {
            case .ghost:   return AgentPalette.bgHover
            case .primary: return AgentPalette.textDisabled
            case .danger:  return Color(red: 0.45, green: 0.18, blue: 0.18)
            }
        }
        switch style {
        case .ghost:   return AgentPalette.bgElevated
        case .primary: return AgentPalette.inverse
        case .danger:  return Color(red: 0.30, green: 0.10, blue: 0.10)
        }
    }

    private var textColor: Color {
        switch style {
        case .ghost:   return AgentPalette.textPrimary
        case .primary: return AgentPalette.inverseInk
        case .danger:  return Color(red: 0.95, green: 0.70, blue: 0.70)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        style == .ghost ? AgentPalette.border : Color.clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Error Banner

/// 顶部错误条。
struct AgentErrorBanner: View {
    let message: String
    var onDismiss: () -> Void
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.20))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AgentPalette.textPrimary)
                .lineLimit(2)
            Spacer()
            if let onRetry = onRetry {
                Button("重试") { onRetry() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AgentPalette.textPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(AgentPalette.border, lineWidth: 0.5)
                    )
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AgentPalette.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color(red: 0.18, green: 0.13, blue: 0.06)
        )
        .overlay(
            Rectangle()
                .fill(Color(red: 0.95, green: 0.65, blue: 0.20).opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Loading / Empty

/// 加载占位。
struct AgentLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.0)
                .colorScheme(.dark)
            Text(AgentText.loadingTitle)
                .font(.system(size: 12))
                .foregroundColor(AgentPalette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 空状态。
struct AgentEmptyView: View {
    var onNewProfile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(AgentPalette.border, lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: "person.2")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(AgentPalette.textMuted)
            }
            Text(AgentText.emptyTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Text(AgentText.emptyHint)
                .font(.system(size: 12))
                .foregroundColor(AgentPalette.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            ToolbarPrimaryButton(
                title: AgentText.newProfile,
                systemImage: "plus",
                action: onNewProfile
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Distribution Card Highlight

/// Distribution 高亮徽章（贴在 profile 卡片右上角）。
struct DistributionBadge: View {
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(AgentPalette.statusDistribution)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(AgentPalette.statusDistribution.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(AgentPalette.statusDistribution.opacity(0.4), lineWidth: 0.5)
        )
    }
}
