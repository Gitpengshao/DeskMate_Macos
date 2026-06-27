import SwiftUI

// MARK: - Palette (Monochrome, 对齐 MainSidebar / MainContentArea)

/// 黑白主题色板 — 与项目内其它黑色主题页面保持一致。
enum MCPalette {
    static let bgBase       = Color(red: 0.000, green: 0.000, blue: 0.000)  // #000000
    static let bgPanel      = Color(red: 0.039, green: 0.039, blue: 0.039)  // #0A0A0A
    static let bgElevated   = Color(red: 0.078, green: 0.078, blue: 0.078)  // #141414
    static let bgHover      = Color(red: 0.110, green: 0.110, blue: 0.110)  // #1C1C1C
    static let border       = Color(red: 0.149, green: 0.149, blue: 0.149)  // #262626
    static let borderStrong = Color(red: 0.260, green: 0.260, blue: 0.260)  // #424242
    static let textPrimary  = Color(red: 1.000, green: 1.000, blue: 1.000)  // #FFFFFF
    static let textSecond   = Color(red: 0.640, green: 0.640, blue: 0.640)  // #A3A3A3
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)  // #6B6B6B
    static let inverse      = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let inverseInk   = Color(red: 0.000, green: 0.000, blue: 0.000)
}

// MARK: - Section Header

/// 段落标题：图标 + 标题 + 描述 + 可选尾部按钮。
struct SectionHeader: View {
    let icon: String
    let title: String
    let description: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(MCPalette.bgElevated)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MCPalette.textPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MCPalette.textPrimary)
                Text(description)
                    .font(.system(size: 11.5))
                    .foregroundColor(MCPalette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let trailing = trailing {
                trailing
            }
        }
    }
}

// MARK: - Current Model Card

/// 当前主模型展示卡片。
struct CurrentModelCard: View {
    let state: ModelConfigModel
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(MCPalette.bgElevated)
                    .frame(width: 40, height: 40)
                Text(state.avatarLetter.isEmpty ? "M" : state.avatarLetter)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MCPalette.textPrimary)
            }
            .overlay(
                Circle().stroke(MCPalette.borderStrong, lineWidth: 1)
            )

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(displayTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(MCPalette.textPrimary)
                    if state.hasModel {
                        Text("正在使用")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(MCPalette.textPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(MCPalette.inverse.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(MCPalette.borderStrong, lineWidth: 1)
                                    )
                            )
                    }
                }

                Text(displaySubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(MCPalette.textSecond)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let key = state.apiKey, !key.isEmpty {
                    Text(maskApiKey(key))
                        .font(.system(size: 11))
                        .foregroundColor(MCPalette.textTertiary)
                }
            }

            Spacer(minLength: 8)

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MCPalette.textSecond)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(MCPalette.bgElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(MCPalette.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("编辑主模型")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(MCPalette.bgElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MCPalette.borderStrong, lineWidth: 1.5)
        )
    }

    private var displayTitle: String {
        if state.providerType == .custom {
            return state.modelId.isEmpty ? "未配置" : state.modelId
        }
        if !state.providerLabel.isEmpty {
            return state.providerLabel
        }
        return state.modelId.isEmpty ? "未配置" : state.modelId
    }

    private var displaySubtitle: String {
        if state.providerType == .custom {
            return state.baseUrl ?? "自定义模型"
        }
        let label = state.providerLabel.isEmpty ? state.providerKey : state.providerLabel
        return "\(label) · \(state.modelId)"
    }
}

// MARK: - Auxiliary Task Row

/// 单个辅助任务行。
struct AuxiliaryTaskRow: View {
    let task: AuxiliaryTaskType
    let config: AuxiliaryModelConfig
    var isHighlighted: Bool = false
    let onChange: () -> Void
    let onReset: () -> Void

    private var isOverridden: Bool { !config.isAuto }

    var body: some View {
        HStack(spacing: 12) {
            // Task icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(MCPalette.bgElevated)
                    .frame(width: 32, height: 32)
                Image(systemName: task.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MCPalette.textPrimary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHighlighted ? MCPalette.inverse.opacity(0.6) : MCPalette.border,
                        lineWidth: 1
                    )
            )

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MCPalette.textPrimary)
                    if isOverridden {
                        Text("已覆盖")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(MCPalette.textPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(MCPalette.inverse.opacity(0.12))
                            )
                    }
                }
                Text(isOverridden
                     ? "\(config.provider ?? "") · \(config.model ?? "")"
                     : "跟随主模型（自动）")
                    .font(.system(size: 11))
                    .foregroundColor(MCPalette.textSecond)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isOverridden, let key = config.apiKey, !key.isEmpty {
                    Text(maskApiKey(key))
                        .font(.system(size: 11))
                        .foregroundColor(MCPalette.textTertiary)
                }
            }

            Spacer(minLength: 8)

            // Action buttons
            TextButton(label: isOverridden ? "更改" : "设置", onTap: onChange)
            if isOverridden {
                TextButton(label: "重置", subtle: true, onTap: onReset)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(MCPalette.bgElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isHighlighted ? MCPalette.inverse.opacity(0.45) : MCPalette.border,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Text Button

/// 简洁的文本按钮（白底 / 透明底）。
struct TextButton: View {
    let label: String
    var subtle: Bool = false
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 11.5, weight: subtle ? .regular : .semibold))
                .foregroundColor(
                    subtle ? MCPalette.textTertiary : MCPalette.textPrimary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(subtle ? Color.clear : MCPalette.inverse.opacity(isHovered ? 0.12 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            subtle ? MCPalette.border : MCPalette.borderStrong,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Toggle Chip

/// 内置 / 自定义切换 chip。
struct ProviderTypeToggleChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(
                    isSelected ? MCPalette.inverseInk : MCPalette.textPrimary
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(corRadius: 8)
                        .fill(isSelected ? MCPalette.inverse : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MCPalette.borderStrong, lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private extension RoundedRectangle {
    init(corRadius: CGFloat) {
        self.init(cornerRadius: corRadius, style: .continuous)
    }
}

// MARK: - Mask API Key

/// 脱敏 API Key：保留前 4 + 后 4，中间用 "..."。
func maskApiKey(_ key: String) -> String {
    if key.count <= 8 {
        return "\(key.prefix(4))..."
    }
    let prefix = key.prefix(4)
    let suffix = key.suffix(4)
    return "\(prefix)...\(suffix)"
}
