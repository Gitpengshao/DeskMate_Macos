import SwiftUI

/// 技能管理页 — 从 Dashboard API 获取技能，支持启用/禁用切换与创建自定义技能。
///
/// UI 风格：黑白主题，灰阶区分层次，每个技能展示名称、描述、路径与启用开关。
struct SkillManagementPage: View {
    @StateObject private var viewModel = SkillManagementViewModel()
    @State private var showingCreateSheet = false

    var body: some View {
        ZStack {
            SMPalette.bgBase.ignoresSafeArea()
            VStack(spacing: 0) {
                pageHeader
                errorBanner
                categoryFilterBar
                Divider()
                    .overlay(SMPalette.divider)
                SMSkillCategoryList(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingCreateSheet) {
            SMCreateSkillDialog(viewModel: viewModel)
        }
    }

    // MARK: - Category Filter

    @ViewBuilder
    private var categoryFilterBar: some View {
        if !viewModel.model.allCategories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SMCategoryTag(
                        title: SMText.allCategories,
                        count: viewModel.model.allSkills.count,
                        isSelected: viewModel.model.selectedCategory == nil,
                        action: { viewModel.selectCategory(nil) }
                    )

                    ForEach(viewModel.model.allCategories, id: \.name) { category in
                        SMCategoryTag(
                            title: category.name,
                            count: category.count,
                            isSelected: viewModel.model.selectedCategory == category.name,
                            action: { viewModel.selectCategory(category.name) }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .background(SMPalette.bgBase)
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(SMPalette.textPrimary)
                    Text(SMText.pageTitle)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(SMPalette.textPrimary)
                }
                Text(SMText.pageSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(SMPalette.textMuted)
            }
            Spacer()

            // 创建技能
            Button(action: {
                showingCreateSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(SMText.createSkill)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(SMPalette.inverseInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SMPalette.inverse)
                )
            }
            .buttonStyle(.plain)

            // 刷新按钮
            Button(action: {
                Task { await viewModel.refreshSkills() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("刷新")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(SMPalette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SMPalette.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(SMPalette.border, lineWidth: 0.56)
                )
            }
            .buttonStyle(.plain)

            // 浏览技能市场
            Button(action: {
                viewModel.browseRegistry()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text(SMText.browseRegistry)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(SMPalette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(SMPalette.border, lineWidth: 0.56)
                )
            }
            .buttonStyle(.plain)
            .help("打开官方可选技能市场文档")
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBanner: some View {
        if let message = viewModel.model.errorMessage, !message.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SMPalette.statusError)
                Text("\(SMText.errorPrefix)\(message)")
                    .font(.system(size: 12))
                    .foregroundColor(SMPalette.statusError)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(action: {
                    Task { await viewModel.refreshSkills() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SMPalette.statusError)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(SMPalette.statusError.opacity(0.1))
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SkillManagementPage_Previews: PreviewProvider {
    static var previews: some View {
        SkillManagementPage()
            .frame(width: 900, height: 700)
    }
}
#endif
