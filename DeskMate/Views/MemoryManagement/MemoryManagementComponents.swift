import SwiftUI

// MARK: - Config Bar

/// 顶部功能开关栏：控制 `memory.memory_enabled` 与 `memory.user_profile_enabled`。
struct MMConfigBar: View {
    @ObservedObject var viewModel: MemoryManagementViewModel

    var body: some View {
        HStack(spacing: 24) {
            toggle(
                title: MMText.toggleMemoryEnabled,
                subtitle: MMText.toggleMemorySubtitle,
                isOn: viewModel.model.memoryEnabled
            ) { isOn in
                viewModel.setMemoryEnabled(isOn)
            }

            toggle(
                title: MMText.toggleUserProfileEnabled,
                subtitle: MMText.toggleUserProfileSubtitle,
                isOn: viewModel.model.userProfileEnabled
            ) { isOn in
                viewModel.setUserProfileEnabled(isOn)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(MMPalette.bgPanel)
        .overlay(
            Rectangle()
                .fill(MMPalette.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func toggle(
        title: String,
        subtitle: String,
        isOn: Bool,
        action: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MMPalette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(MMPalette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(get: { isOn }, set: { action($0) }))
                .toggleStyle(SwitchToggleStyle(tint: MMPalette.textPrimary))
                .labelsHidden()
                .frame(width: 44)
        }
        .frame(width: 220)
    }
}

// MARK: - Tab Bar

/// 顶部 Tab 栏：记忆 / 用户画像 / 灵魂画像。
struct MMTabBar: View {
    @ObservedObject var viewModel: MemoryManagementViewModel

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.memory, title: MMText.tabMemory)
            tabButton(.userProfile, title: MMText.tabUserProfile)
            tabButton(.soulProfile, title: MMText.tabSoulProfile)
        }
        .padding(.horizontal, 20)
        .overlay(
            Rectangle()
                .fill(MMPalette.border)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func tabButton(_ tab: MemoryTab, title: String) -> some View {
        let isActive = viewModel.model.activeTab == tab
        Button(action: { viewModel.switchTab(tab) }) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundColor(
                        isActive ? MMPalette.textPrimary : MMPalette.textMuted
                    )
                    .frame(height: 20)
                Rectangle()
                    .fill(isActive ? MMPalette.textPrimary : Color.clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Capacity Bar

/// 容量信息行 + 新增按钮（灵魂画像 Tab 下隐藏新增按钮）。
struct MMCapacityBar: View {
    @ObservedObject var viewModel: MemoryManagementViewModel
    var onAdd: () -> Void

    var body: some View {
        HStack {
            Text(MMText.capacity(
                used: formatNumber(viewModel.model.usedCapacity),
                total: formatNumber(viewModel.model.maxCapacity),
                entries: "\(viewModel.model.totalEntries)"
            ))
            .font(.system(size: 11))
            .foregroundColor(MMPalette.textMuted)
            Spacer()
            if canAddEntry {
                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                        Text(MMText.addEntry)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(MMPalette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(MMPalette.bgHover)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(MMPalette.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var canAddEntry: Bool {
        switch viewModel.model.activeTab {
        case .soulProfile:
            return false
        case .memory:
            return viewModel.model.memoryEnabled
        case .userProfile:
            return viewModel.model.userProfileEnabled
        }
    }
}

// MARK: - Error Banner

/// 顶部错误提示栏，可关闭。
struct MMErrorBanner: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundColor(MMPalette.statusError)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(MMPalette.statusError)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MMPalette.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(MMPalette.statusErrorBg)
    }
}

// MARK: - Loading / Empty States

struct MMLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .colorScheme(.dark)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(MMPalette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MMEmptyView: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(MMPalette.textMuted)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(MMPalette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Disabled Feature State

/// 功能被禁用时展示的占位视图。
struct MMDisabledFeatureView: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(MMPalette.textMuted)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(MMPalette.textMuted)
                Text(MMText.disabledSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(MMPalette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Memory Item Row

/// 单条记忆条目行。
struct MMMemoryItemRow: View {
    let index: Int
    let entry: MemoryEntry
    var canDelete: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Index
            Text("\(index)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MMPalette.textMuted)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 2)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content)
                    .font(.system(size: 13))
                    .foregroundColor(MMPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(targetLabel(for: entry.target))
                    .font(.system(size: 11))
                    .foregroundColor(MMPalette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Actions
            HStack(spacing: 4) {
                MMActionButton(icon: "pencil", onTap: onEdit)
                if canDelete {
                    MMActionButton(icon: "trash", onTap: onDelete)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            isHovered ? MMPalette.bgHover : MMPalette.bgElevated
        )
        .overlay(
            Rectangle()
                .fill(MMPalette.border)
                .frame(height: 1),
            alignment: .bottom
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    private func targetLabel(for target: MemoryTarget) -> String {
        switch target {
        case .memory: return "MEMORY.md"
        case .user:   return "USER.md"
        case .soul:   return "SOUL.md"
        }
    }
}

/// 单个操作按钮（编辑/删除），带 hover 高亮。
struct MMActionButton: View {
    let icon: String
    var onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(MMPalette.textMuted)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? MMPalette.bgBase : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MMPalette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
