import SwiftUI
import AppKit

/// 多智能体协同页 — 简化为左侧智能体列表 + 右侧会话。
///
/// 布局：
/// ```
/// ┌────────────────────────────────────────────────────────────┐
/// │ 多智能体协同  副标题                         刷新    + 新建 │
/// ├──────────────────────┬─────────────────────────────────────┤
/// │ 搜索框 / 计数 chips  │                                     │
/// │ ──────────────────── │   AiChatPage（按 profile 隔离）      │
/// │ 列表行 (选中)        │                                     │
/// │ 列表行               │                                     │
/// │ ...                  │                                     │
/// └──────────────────────┴─────────────────────────────────────┘
/// ```
struct AgentPage: View {

    // MARK: - State

    /// 使用共享 ViewModel，跨 tab 切换时保持同一个实例，
    /// 避免每次进入页面都重新走一次 loading。
    /// 注意：共享单例必须使用 @ObservedObject，而不是 @StateObject。
    @ObservedObject private var viewModel = AgentViewModel.shared

    /// 对话框可见性
    @State private var showNewProfileDialog: Bool = false

    /// 行内编辑弹窗直接绑定到对应 profile（避免 dialogProfile + showXxxDialog 双状态不同步）。
    @State private var renameDialogProfile: AgentProfile? = nil
    @State private var deleteDialogProfile: AgentProfile? = nil
    @State private var describeDialogProfile: AgentProfile? = nil
    @State private var modelDialogProfile: AgentProfile? = nil
    @State private var soulDialogProfile: AgentProfile? = nil
    @State private var skillsDialogProfile: AgentProfile? = nil

    // MARK: - Init

    init() {}

    // MARK: - Body

    var body: some View {
        let _ = DMLogger.log(
            "[AgentPage] body selected=\(viewModel.model.selectedProfileId)",
            name: "AgentPage"
        )
        ZStack {
            mainContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AgentPalette.bgBase)
        .sheet(isPresented: $showNewProfileDialog) {
            NewAgentProfileDialog(viewModel: viewModel)
        }
        .sheet(item: $renameDialogProfile) { p in
            RenameAgentProfileDialog(viewModel: viewModel, profile: p)
        }
        .sheet(item: $deleteDialogProfile) { p in
            DeleteAgentProfileDialog(viewModel: viewModel, profile: p)
        }
        .sheet(item: $describeDialogProfile) { p in
            DescribeAgentProfileDialog(viewModel: viewModel, profile: p)
        }
        .sheet(item: $modelDialogProfile) { p in
            let _ = DMLogger.log(
                "[AgentPage] sheet model profileId=\(p.id)",
                name: "AgentPage"
            )
            EditAgentModelDialog(profile: p)
        }
        .sheet(item: $soulDialogProfile) { p in
            let _ = DMLogger.log(
                "[AgentPage] sheet soul profileId=\(p.id)",
                name: "AgentPage"
            )
            EditAgentSoulDialog(viewModel: viewModel, profile: p)
        }
        .sheet(item: $skillsDialogProfile) { p in
            let _ = DMLogger.log(
                "[AgentPage] sheet skills profileId=\(p.id)",
                name: "AgentPage"
            )
            EditAgentSkillsDialog(viewModel: viewModel, profile: p)
        }
        // ⌘R 刷新
        .background(
            Button("") { Task { await viewModel.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        )
        // ⌘N 新建
        .background(
            Button("") { showNewProfileDialog = true }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        )
        // 页面每次出现时触发一次静默后台刷新：
        // - 首次冷启动由 `init` 触发全屏加载；
        // - 之后每次切到该 tab 都立即展示缓存，并后台静默拉新数据。
        .task {
            await viewModel.silentRefresh()
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let err = viewModel.model.errorMessage.isEmpty ? nil : viewModel.model.errorMessage {
                AgentErrorBanner(
                    message: err,
                    onDismiss: { viewModel.clearError() },
                    onRetry: { Task { await viewModel.refresh() } }
                )
            }

            // 仅在没有缓存、且正在进行首次加载时才显示全屏 loading；
            // 有缓存时立即展示上一次的列表，由 `silentRefresh()` 在后台静默更新。
            if viewModel.model.isLoading && !viewModel.model.hasCache {
                AgentLoadingView()
            } else {
                pageLayout
            }
        }
    }

    @ViewBuilder
    private var pageLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader
            Divider().overlay(AgentPalette.divider)
            contentRow
        }
    }

    // MARK: - Page Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AgentPalette.textPrimary)
                        Text(AgentText.pageTitle)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(AgentPalette.textPrimary)
                        // 静默后台刷新时的微提示 — 不打断用户阅读。
                        if viewModel.model.isBackgroundRefreshing {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.55)
                                    .frame(width: 10, height: 10)
                                Text("后台同步中")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(AgentPalette.textMuted)
                            }
                        }
                    }
                    Text(AgentText.pageSubtitle)
                        .font(.system(size: 12))
                        .foregroundColor(AgentPalette.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                AgentToolbar(
                    viewModel: viewModel,
                    onNewProfile: { showNewProfileDialog = true }
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    // MARK: - Content Row (left list + right chat)

    @ViewBuilder
    private var contentRow: some View {
        HStack(spacing: 0) {
            // 左侧：profile 列表
            sidePanel
                .frame(width: 320)
                .background(AgentPalette.sidePanel)
                .overlay(
                    Rectangle()
                        .fill(AgentPalette.divider)
                        .frame(width: 1),
                    alignment: .trailing
                )

            // 右侧：会话
            chatPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Side Panel

    private var sidePanel: some View {
        VStack(spacing: 0) {
            AgentSideFilter(viewModel: viewModel)
            Divider().overlay(AgentPalette.divider)
            profileList
        }
    }

    @ViewBuilder
    private var profileList: some View {
        let _ = DMLogger.log(
            "[AgentPage] profileList body selected=\(viewModel.model.selectedProfileId)",
            name: "AgentPage"
        )
        if viewModel.model.filteredProfiles.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 20))
                    .foregroundColor(AgentPalette.textMuted)
                Text("没有匹配的 profile")
                    .font(.system(size: 12))
                    .foregroundColor(AgentPalette.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.model.filteredProfiles) { p in
                        AgentProfileRow(
                            profile: p,
                            isSelected: p.id == viewModel.model.selectedProfileId,
                            onTap: {
                                let start = Date()
                                DMLogger.log(
                                    "[AgentPage] row tap START profileId=\(p.id) selected=\(viewModel.model.selectedProfileId)",
                                    name: "AgentPage"
                                )
                                viewModel.selectProfile(p.id)
                                DMLogger.log(
                                    "[AgentPage] row tap DONE profileId=\(p.id) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s",
                                    name: "AgentPage"
                                )
                            },
                            onDescribe: {
                                logEditTap(p, kind: "describe")
                                describeDialogProfile = p
                            },
                            onEditModel: {
                                logEditTap(p, kind: "model")
                                modelDialogProfile = p
                            },
                            onEditSoul: {
                                logEditTap(p, kind: "soul")
                                soulDialogProfile = p
                            },
                            onEditSkills: {
                                logEditTap(p, kind: "skills")
                                skillsDialogProfile = p
                            },
                            onRename: {
                                logEditTap(p, kind: "rename")
                                renameDialogProfile = p
                            },
                            onDelete: {
                                logEditTap(p, kind: "delete")
                                deleteDialogProfile = p
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Chat Panel

    @ViewBuilder
    private var chatPanel: some View {
        let profileId = viewModel.model.selectedProfileId
        let _ = DMLogger.log(
            "[AgentPage] chatPanel body selected=\(profileId) preparing=\(viewModel.preparingProfileId ?? "nil") container=\(viewModel.chatContainer(for: profileId) != nil ? "yes" : "no")",
            name: "AgentPage"
        )
        if !profileId.isEmpty {
            if viewModel.preparingProfileId == profileId {
                preparingView(profileId: profileId)
            } else if let container = viewModel.chatContainer(for: profileId) {
                AiChatPage(chatVM: container.chatVM, sessionVM: container.sessionVM, isDark: true)
            } else {
                startFailedView(profileId: profileId)
            }
        } else {
            AgentEmptyView(onNewProfile: { showNewProfileDialog = true })
        }
    }

    private func preparingView(profileId: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.0)
                .tint(AgentPalette.textPrimary)
            Text("正在启动 \(profileId) 的 Gateway…")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AgentPalette.textPrimary)
            Text("首次切换需要等待 Hermes Gateway 就绪")
                .font(.system(size: 11))
                .foregroundColor(AgentPalette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AgentPalette.bgBase)
    }

    private func startFailedView(profileId: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(AgentPalette.textMuted)
            Text("无法启动 \(profileId) 的 Gateway")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AgentPalette.textPrimary)
            Button("重试") {
                DMLogger.log("[AgentPage] retry selectProfile=\(profileId)", name: "AgentPage")
                viewModel.selectProfile(profileId)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(AgentPalette.inverseInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AgentPalette.inverse)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AgentPalette.bgBase)
    }

    private func logEditTap(_ profile: AgentProfile, kind: String) {
        DMLogger.log(
            "[AgentPage] edit tap: kind=\(kind) profileId=\(profile.id) " +
            "name=\(profile.name) descLen=\(profile.description.count) " +
            "model=\(profile.model) isDefault=\(profile.isDefault)",
            name: "AgentPage"
        )
    }
}

// MARK: - Preview

#if DEBUG
struct AgentPage_Previews: PreviewProvider {
    static var previews: some View {
        AgentPage()
            .frame(width: 1100, height: 760)
    }
}
#endif
