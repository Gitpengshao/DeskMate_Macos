import SwiftUI

/// 技能管理页 — 一比一还原 Flutter `SkillManagementPage`。
///
/// 两个 Tab：
/// - **内置技能** — `~/.hermes/skills/.bundled_manifest` 中列出的技能
/// - **可用技能** — 安装在 `~/.hermes/skills/` 下但不在内置清单中的技能
///
/// UI 风格：黑白主题，灰阶区分层次，每个技能展示名称、描述、路径与操作按钮。
struct SkillManagementPage: View {
    @StateObject private var viewModel = SkillManagementViewModel()

    var body: some View {
        ZStack {
            SMPalette.bgBase.ignoresSafeArea()
            VStack(spacing: 0) {
                pageHeader
                SMTabBar(viewModel: viewModel)
                Divider()
                    .overlay(SMPalette.divider)
                SMSkillCategoryList(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
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
