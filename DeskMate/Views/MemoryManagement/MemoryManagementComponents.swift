import SwiftUI

// MARK: - Tab Bar

/// 顶部 Tab 栏：记忆 / 用户画像 / Provider。
struct MMTabBar: View {
    @ObservedObject var viewModel: MemoryManagementViewModel

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.memory, title: MMText.tabMemory)
            tabButton(.userProfile, title: MMText.tabUserProfile)
            tabButton(.providers, title: MMText.tabProviders)
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

/// 容量信息行 + 新增按钮（Providers Tab 下仅显示标题）。
struct MMCapacityBar: View {
    @ObservedObject var viewModel: MemoryManagementViewModel
    var onAdd: () -> Void

    var body: some View {
        Group {
            if viewModel.model.activeTab == .providers {
                HStack {
                    Text(MMText.providersHeader)
                        .font(.system(size: 11))
                        .foregroundColor(MMPalette.textMuted)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            } else {
                HStack {
                    Text(MMText.capacity(
                        used: formatNumber(viewModel.model.usedCapacity),
                        total: formatNumber(viewModel.model.maxCapacity),
                        entries: "\(viewModel.model.totalEntries)"
                    ))
                    .font(.system(size: 11))
                    .foregroundColor(MMPalette.textMuted)
                    Spacer()
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
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
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

// MARK: - Memory Item Row

/// 单条记忆条目行。
struct MMMemoryItemRow: View {
    let index: Int
    let entry: MemoryEntry
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
                Text(entry.target == .memory ? "MEMORY.md" : "USER.md")
                    .font(.system(size: 11))
                    .foregroundColor(MMPalette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Actions
            HStack(spacing: 4) {
                MMActionButton(icon: "pencil", onTap: onEdit)
                MMActionButton(icon: "trash", onTap: onDelete)
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

// MARK: - Provider Card

/// 单个外部记忆 Provider 卡片。
struct MMProviderCard: View {
    let provider: MemoryProviderInfo
    @ObservedObject var viewModel: MemoryManagementViewModel

    /// endpoint 徽章 hover 状态。
    @State private var isEndpointHovered: Bool = false

    var body: some View {
        let isActive = viewModel.model.activeProvider == provider.id
        let isRunning = isActive && viewModel.model.providerStatus == .running
        let isInstalling = isActive && viewModel.model.providerStatus == .installing
        let isError = isActive && viewModel.model.providerStatus == .error
        let isStopped = isActive && viewModel.model.providerStatus == .stopped

        let (statusLabel, statusColor) = statusInfo(
            isRunning: isRunning,
            isInstalling: isInstalling,
            isError: isError,
            isStopped: isStopped,
            isActive: isActive
        )

        VStack(alignment: .leading, spacing: 14) {
            // Header: icon + name/status + toggle
            HStack(alignment: .center, spacing: 12) {
                // Icon box
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MMPalette.border, lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(MMPalette.bgBase)
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "cylinder.split.1x2")
                        .font(.system(size: 16))
                        .foregroundColor(
                            isRunning ? MMPalette.statusRunning : MMPalette.textMuted
                        )
                }

                // Name + status
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MMPalette.textPrimary)
                    HStack(spacing: 6) {
                        if isInstalling {
                            ProgressView()
                                .controlSize(.mini)
                                .colorScheme(.dark)
                                .scaleEffect(0.7)
                        }
                        if isRunning {
                            Circle()
                                .fill(MMPalette.statusRunning)
                                .frame(width: 6, height: 6)
                        }
                        Text(statusLabel)
                            .font(.system(size: 11))
                            .foregroundColor(statusColor)
                    }
                }

                Spacer()

                // Toggle
                MMToggleSwitch(
                    isOn: isActive,
                    disabled: isInstalling
                ) {
                    viewModel.toggleOpenViking(!isActive)
                }
            }

            // Description
            Text(provider.description)
                .font(.system(size: 12))
                .foregroundColor(MMPalette.textMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // Detail rows
            VStack(alignment: .leading, spacing: 6) {
                providerDetailRow(label: MMText.providerBestFor, value: provider.bestFor)
                providerDetailRow(label: MMText.providerRequires, value: provider.requires)
                providerDetailRow(label: MMText.providerStorage, value: provider.dataStorage)
                providerDetailRow(label: MMText.providerCost, value: provider.cost)
            }

            // Python interpreter row
            pythonRow

            // Endpoint badge (only when running) — 点击启动新进程打开 WebView 窗口
            if isRunning, let endpoint = viewModel.model.providerEndpoint {
                endpointBadge(endpoint: endpoint)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(MMPalette.bgElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isRunning ? MMPalette.statusRunning : MMPalette.border,
                    lineWidth: isRunning ? 1.5 : 1
                )
        )
    }

    private func statusInfo(
        isRunning: Bool,
        isInstalling: Bool,
        isError: Bool,
        isStopped: Bool,
        isActive: Bool
    ) -> (String, Color) {
        if isRunning {
            return (MMText.providerRunning, MMPalette.statusRunning)
        }
        if isInstalling {
            return (
                viewModel.model.providerStatusMessage ?? MMText.providerInstalling,
                MMPalette.statusInstalling
            )
        }
        if isError {
            return (
                viewModel.model.providerStatusMessage ?? MMText.providerError,
                MMPalette.statusError
            )
        }
        if isStopped {
            return (MMText.providerStopped, MMPalette.statusInstalling)
        }
        return (MMText.providerDisabled, MMPalette.textMuted)
    }

    private func providerDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(MMPalette.textTertiary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(MMPalette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Provider 服务地址徽章 — 整体可点击，点击后启动新进程打开 WebView 窗口。
    private func endpointBadge(endpoint: String) -> some View {
        Button(action: {
            viewModel.openProviderWebView(endpoint)
        }) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(MMPalette.textMuted)
                Text(endpoint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(MMPalette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                    .foregroundColor(
                        isEndpointHovered
                            ? MMPalette.textPrimary
                            : MMPalette.textMuted
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isEndpointHovered
                            ? MMPalette.bgHover
                            : MMPalette.bgBase
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isEndpointHovered
                            ? MMPalette.textTertiary
                            : MMPalette.border,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isEndpointHovered = hovering
        }
        .help("点击在新窗口中打开 OpenViking Web 界面")
    }

    /// Python 解释器选择行：显示当前路径 + 重新检测/更改按钮。
    @ViewBuilder
    private var pythonRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(MMText.providerPython)
                .font(.system(size: 11))
                .foregroundColor(MMPalette.textTertiary)
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if let path = viewModel.model.pythonPath {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(MMPalette.textMuted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text(MMText.providerPythonNone)
                        .font(.system(size: 11))
                        .foregroundColor(MMPalette.statusError)
                }
                HStack(spacing: 6) {
                    Button(MMText.providerPythonChange) {
                        viewModel.showPythonPicker()
                    }
                    .buttonStyle(MMSecondaryButtonStyle())
                    Button(MMText.providerPythonRescan) {
                        Task { await viewModel.rescanPythonCandidates() }
                    }
                    .buttonStyle(MMSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Toggle Switch

/// 黑白主题的开关控件（避免 SwiftUI Toggle 自带蓝色）。
struct MMToggleSwitch: View {
    let isOn: Bool
    let disabled: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn
                            ? MMPalette.statusRunning
                            : MMPalette.border
                    )
                    .frame(width: 40, height: 22)
                Circle()
                    .fill(MMPalette.textPrimary)
                    .frame(width: 16, height: 16)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }
}
