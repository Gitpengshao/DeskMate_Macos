import SwiftUI

// MARK: - Skill Category List

/// 分类技能列表 — 对齐 Flutter `_SkillCategoryList`。
struct SMSkillCategoryList: View {
    @ObservedObject var viewModel: SkillManagementViewModel

    var body: some View {
        if viewModel.model.isLoading && viewModel.model.skills.isEmpty {
            SMLoadingView(title: SMText.loading)
        } else if viewModel.model.filteredSkills.isEmpty {
            SMEmptyView(
                icon: "tray",
                title: SMText.emptyAll
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.model.filteredSkills) { group in
                        SMCategorySection(
                            group: group,
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
                        onToggle: { viewModel.toggleSkill(skill.id) }
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
    var onToggle: () -> Void

    @State private var localEnabled: Bool

    init(skill: SkillItem, onToggle: @escaping () -> Void) {
        self.skill = skill
        self.onToggle = onToggle
        _localEnabled = State(initialValue: skill.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row + status badge
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
                } else {
                    Text(SMText.badgeDisabled)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SMPalette.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SMPalette.bgElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(SMPalette.border, lineWidth: 0.56)
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

            // Toggle row
            HStack(spacing: 8) {
                Spacer()
                if skill.isToggling {
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                        .frame(width: 38, height: 22)
                } else {
                    Toggle(skill.isEnabled ? SMText.actionDisable : SMText.actionEnable, isOn: $localEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(skill.isToggling)
                        .onChange(of: localEnabled) { newValue in
                            if newValue != skill.isEnabled {
                                onToggle()
                            }
                        }
                }
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
        .onChange(of: skill.isEnabled) { newValue in
            localEnabled = newValue
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

// MARK: - Category Filter Tag

/// 顶部分类筛选 Tag。
struct SMCategoryTag: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? SMPalette.inverseInk.opacity(0.7) : SMPalette.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? SMPalette.inverseInk.opacity(0.12) : SMPalette.textMuted.opacity(0.12))
                    )
            }
            .foregroundColor(isSelected ? SMPalette.inverseInk : SMPalette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? SMPalette.inverse : SMPalette.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : SMPalette.border, lineWidth: 0.56)
            )
        }
        .buttonStyle(.plain)
    }
}
