import SwiftUI

// MARK: - Tab Bar

/// 顶部 Tab 栏：内置技能 / 可用技能 — 对齐 Flutter `_TabBar` + `_TabChip`。
struct SMTabBar: View {
    @ObservedObject var viewModel: SkillManagementViewModel

    var body: some View {
        HStack(spacing: 24) {
            tabChip(.builtIn, title: SMText.tabBuiltIn)
            tabChip(.available, title: SMText.tabAvailable)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func tabChip(_ tab: SkillFilterTab, title: String) -> some View {
        let isActive = viewModel.model.activeTab == tab
        Button(action: { viewModel.switchTab(tab) }) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 14, weight: isActive ? .medium : .regular))
                    .foregroundColor(isActive ? SMPalette.textPrimary : SMPalette.textMuted)
                    .frame(height: 20)
                Rectangle()
                    .fill(isActive ? SMPalette.textPrimary : Color.clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Skill Category List

/// 分类技能列表 — 对齐 Flutter `_SkillCategoryList`。
struct SMSkillCategoryList: View {
    @ObservedObject var viewModel: SkillManagementViewModel

    var body: some View {
        if viewModel.model.isLoading {
            SMLoadingView(title: SMText.loading)
        } else if viewModel.model.activeGroups.isEmpty {
            SMEmptyView(
                icon: "tray",
                title: viewModel.model.activeTab == .builtIn
                    ? SMText.emptyBuiltIn
                    : SMText.emptyAvailable
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.model.activeGroups) { group in
                        SMCategorySection(
                            group: group,
                            isBuiltIn: viewModel.model.activeTab == .builtIn,
                            viewModel: viewModel
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Category Section

/// 单个分类分组（标题 + 计数 + 技能卡片网格）— 对齐 Flutter `_CategorySection`。
struct SMCategorySection: View {
    let group: SkillCategoryGroup
    let isBuiltIn: Bool
    @ObservedObject var viewModel: SkillManagementViewModel

    private let cardWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(group.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(SMPalette.textHeader)
                Text("\(group.skills.count)")
                    .font(.system(size: 11))
                    .foregroundColor(SMPalette.textHeader)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SMPalette.textHeader.opacity(0.1))
                    )
            }
            .padding(.bottom, 12)

            // 自适应网格：每行尽量容纳多个 300pt 卡片
            let columns = [GridItem(.adaptive(minimum: cardWidth), spacing: 12, alignment: .top)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(group.skills) { skill in
                    SMSkillCard(
                        skill: skill,
                        isBuiltIn: isBuiltIn,
                        onInstall: { viewModel.installSkill(skill.id) },
                        onUninstall: { viewModel.uninstallSkill(skill.id) },
                        onRestore: { viewModel.restoreSkill(skill.id) }
                    )
                }
            }
        }
    }
}

// MARK: - Skill Card

/// 单个技能卡片 — 对齐 Flutter `_SkillCard`。
struct SMSkillCard: View {
    let skill: SkillItem
    let isBuiltIn: Bool
    var onInstall: () -> Void
    var onUninstall: () -> Void
    var onRestore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row + Installed badge
            HStack(alignment: .top, spacing: 8) {
                Text(skill.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(SMPalette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if skill.isEnabled {
                    Text(SMText.badgeInstalled)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SMPalette.statusInstalled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SMPalette.statusInstalledBg)
                        )
                }
            }

            // Description
            Text(skill.description)
                .font(.system(size: 12))
                .foregroundColor(SMPalette.textMuted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .top)

            // Path
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(SMPalette.textMuted)
                Text(SMText.skillsPath(skill.path))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(SMPalette.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Action button
            HStack {
                Spacer()
                actionButton
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(SMPalette.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(SMPalette.border, lineWidth: 0.56)
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        if isBuiltIn {
            // 内置技能：已启用时禁用按钮；未启用时显示 Restore（重新启用）
            Button(action: { if !skill.isEnabled { onRestore() } }) {
                Text(SMText.actionRestore)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(
                        skill.isEnabled ? SMPalette.textDisabled : SMPalette.textMuted
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SMPalette.border, lineWidth: 0.56)
                    )
            }
            .buttonStyle(.plain)
            .disabled(skill.isEnabled)
        } else if skill.isEnabled {
            // 可用技能：已安装时显示 Uninstall
            Button(action: onUninstall) {
                Text(SMText.actionUninstall)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SMPalette.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SMPalette.border, lineWidth: 0.56)
                    )
            }
            .buttonStyle(.plain)
        } else {
            // 可用技能：未安装时显示 Install（实心按钮）
            Button(action: onInstall) {
                Text(SMText.actionInstall)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SMPalette.inverseInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(SMPalette.inverse)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Loading / Empty States

struct SMLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .colorScheme(.dark)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(SMPalette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SMEmptyView: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(SMPalette.textMuted)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(SMPalette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
