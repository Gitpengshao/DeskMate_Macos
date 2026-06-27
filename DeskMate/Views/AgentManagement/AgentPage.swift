import SwiftUI
import AppKit

/// 多智能体协同页 — 一比一还原官方 Hermes profiles 文档的可视化配置：
/// https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/profiles
/// https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/profile-distributions
///
/// 布局：
/// ```
/// ┌────────────────────────────────────────────────────────────────────┐
/// │ 多智能体协同  副标题                                  刷新 文档  安装 │
/// │                                                          + 新建     │
/// ├──────────────────────┬─────────────────────────────────────────────┤
/// │ 搜索框 / 计数 chips  │  [头像] profile.id  [active]  [distrib@ver]  │
/// │  ☐ 仅 distribution   │  description ...                            │
/// │ ──────────────────── │ ─────────────────────────────────────────── │
/// │ 列表行 (选中)        │ AgentDetailSectionHeader 基本信息            │
/// │ 列表行               │  field1    value                            │
/// │ 列表行               │  field2    value                            │
/// │ 列表行               │ AgentDetailSectionHeader 运行时              │
/// │ ...                  │  field     value                            │
/// │                      │ AgentDetailSectionHeader Distribution        │
/// │                      │  ...                                        │
/// │                      │ AgentDetailSectionHeader Gateway            │
/// │                      │  [启动] [停止] [安装为服务]                  │
/// │                      │ AgentDetailSectionHeader 危险操作            │
/// │                      │  [重命名] [导出] [删除]                     │
/// └──────────────────────┴─────────────────────────────────────────────┘
/// ```
struct AgentPage: View {

    // MARK: - State

    /// 使用共享 ViewModel，跨 tab 切换时保持同一个实例，
    /// 避免每次进入页面都重新走一次 loading。
    @StateObject private var viewModel = AgentViewModel.shared

    /// 对话框可见性
    @State private var showNewProfileDialog: Bool = false
    @State private var showInstallDistributionDialog: Bool = false
    @State private var showRenameDialog: Bool = false
    @State private var showDeleteDialog: Bool = false
    @State private var showDescribeDialog: Bool = false

    // MARK: - Init

    init() {}

    // MARK: - Body

    var body: some View {
        ZStack {
            mainContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AgentPalette.bgBase)
        .sheet(isPresented: $showNewProfileDialog) {
            NewAgentProfileDialog(viewModel: viewModel)
        }
        .sheet(isPresented: $showInstallDistributionDialog) {
            InstallDistributionDialog(viewModel: viewModel)
        }
        .sheet(isPresented: $showRenameDialog) {
            if let p = viewModel.model.selectedProfile {
                RenameAgentProfileDialog(viewModel: viewModel, profile: p)
            }
        }
        .sheet(isPresented: $showDeleteDialog) {
            if let p = viewModel.model.selectedProfile {
                DeleteAgentProfileDialog(viewModel: viewModel, profile: p)
            }
        }
        .sheet(isPresented: $showDescribeDialog) {
            if let p = viewModel.model.selectedProfile {
                DescribeAgentProfileDialog(viewModel: viewModel, profile: p)
            }
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
        // ⌘I 安装 distribution
        .background(
            Button("") { showInstallDistributionDialog = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
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
                        if let active = viewModel.model.activeProfile {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(AgentPalette.statusRunning)
                                    .frame(width: 6, height: 6)
                                Text("\(AgentText.currentActive): \(active.id)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AgentPalette.textMuted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(AgentPalette.bgElevated)
                            )
                            .overlay(
                                Capsule().stroke(AgentPalette.border, lineWidth: 0.5)
                            )
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
                    onNewProfile: { showNewProfileDialog = true },
                    onInstallDistribution: { showInstallDistributionDialog = true }
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    // MARK: - Content Row (left list + right detail)

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

            // 右侧：详情
            detailPanel
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
                            onTap: { viewModel.selectProfile(p.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let profile = viewModel.model.selectedProfile {
            profileDetailScroll(profile: profile)
        } else {
            // 没有任何 profile 时显示空状态
            VStack(spacing: 14) {
                Image(systemName: "person.2")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(AgentPalette.textMuted)
                Text("请选择左侧的 profile 查看详情")
                    .font(.system(size: 13))
                    .foregroundColor(AgentPalette.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func profileDetailScroll(profile: AgentProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // ---- Header Card ----
                profileHeaderCard(profile)
                    .padding(.top, 22)

                // ---- 基本信息 ----
                sectionBlock(title: "基本信息", icon: "info.circle") {
                    VStack(alignment: .leading, spacing: 10) {
                        AgentFieldRow(
                            label: AgentText.fieldId,
                            value: profile.id,
                            monospaced: true
                        )
                        AgentFieldRow(
                            label: AgentText.fieldAlias,
                            value: profile.alias,
                            monospaced: true
                        )
                        AgentFieldRow(
                            label: AgentText.fieldPath,
                            value: profile.path,
                            monospaced: true
                        )
                        AgentFieldRow(
                            label: AgentText.fieldDescription,
                            value: profile.description,
                            multiline: true
                        )
                        // 编辑描述按钮
                        HStack {
                            Spacer()
                            DetailActionButton(
                                title: AgentText.editDescription,
                                systemImage: "pencil",
                                action: { showDescribeDialog = true }
                            )
                        }
                    }
                }

                // ---- 运行时 ----
                sectionBlock(title: "运行时", icon: "cpu") {
                    VStack(alignment: .leading, spacing: 10) {
                        AgentFieldRow(
                            label: AgentText.fieldModel,
                            value: profile.model.isEmpty
                                ? "未配置"
                                : profile.model,
                            monospaced: true
                        )
                        AgentFieldRow(
                            label: AgentText.fieldProvider,
                            value: profile.provider.isEmpty
                                ? "—"
                                : profile.provider,
                            monospaced: true
                        )
                        AgentFieldRow(
                            label: AgentText.fieldSkills,
                            value: "\(profile.skillsCount)"
                        )
                        AgentFieldRow(
                            label: AgentText.fieldCron,
                            value: "\(profile.cronCount)"
                        )
                        if !profile.installedAt.isEmpty {
                            AgentFieldRow(
                                label: AgentText.fieldInstalledAt,
                                value: profile.installedAt,
                                monospaced: true
                            )
                        }
                    }
                }

                // ---- Distribution ----
                if profile.isDistribution {
                    sectionBlock(title: "Distribution", icon: "shippingbox.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            AgentFieldRow(
                                label: AgentText.fieldDistName,
                                value: profile.distributionName,
                                monospaced: true
                            )
                            AgentFieldRow(
                                label: AgentText.fieldDistVersion,
                                value: profile.distributionVersion,
                                monospaced: true
                            )
                            if !profile.distributionSource.isEmpty {
                                AgentFieldRow(
                                    label: AgentText.fieldDistSource,
                                    value: profile.distributionSource,
                                    monospaced: true
                                )
                            }
                            if !profile.distributionAuthor.isEmpty {
                                AgentFieldRow(
                                    label: AgentText.fieldDistAuthor,
                                    value: profile.distributionAuthor
                                )
                            }
                            if !profile.distributionLicense.isEmpty {
                                AgentFieldRow(
                                    label: AgentText.fieldDistLicense,
                                    value: profile.distributionLicense
                                )
                            }
                            HStack {
                                Spacer()
                                DetailActionButton(
                                    title: AgentText.updateDistribution,
                                    systemImage: "arrow.triangle.2.circlepath",
                                    action: {
                                        Task { await viewModel.updateDistribution(profile.id) }
                                    }
                                )
                            }
                        }
                    }
                }

                // ---- Gateway ----
                sectionBlock(title: "Gateway", icon: "antenna.radiowaves.left.and.right") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(profile.gatewayStatus.dotColor)
                                .frame(width: 10, height: 10)
                            Text(profile.gatewayStatus.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AgentPalette.textPrimary)
                            Spacer()
                            Text("进程端口: \(AppConstants.defaultGatewayPort)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(AgentPalette.textMuted)
                        }
                        HStack(spacing: 8) {
                            if profile.gatewayStatus == .running {
                                DetailActionButton(
                                    title: AgentText.stopGateway,
                                    systemImage: "stop.circle",
                                    action: {
                                        Task { await viewModel.stopGateway(for: profile.id) }
                                    }
                                )
                            } else {
                                DetailActionButton(
                                    title: AgentText.startGateway,
                                    systemImage: "play.circle",
                                    style: .primary,
                                    action: {
                                        Task { await viewModel.startGateway(for: profile.id) }
                                    }
                                )
                            }
                            DetailActionButton(
                                title: AgentText.installService,
                                systemImage: "gear.badge",
                                action: {
                                    Task { await viewModel.installGatewayService(for: profile.id) }
                                }
                            )
                        }
                        Text("""
每个 profile 拥有独立的 gateway 进程，使用各自的 bot token。
若两个 profile 意外使用相同 token，第二个 gateway 会被阻止并报告冲突 profile。
""")
                            .font(.system(size: 11))
                            .foregroundColor(AgentPalette.textMuted)
                            .lineSpacing(2)
                    }
                }

                // ---- 危险操作 ----
                sectionBlock(title: "危险操作", icon: "exclamationmark.triangle") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            if !profile.isActive && !profile.isDefault {
                                DetailActionButton(
                                    title: AgentText.useAsActive,
                                    systemImage: "checkmark.circle",
                                    style: .primary,
                                    action: {
                                        Task { await viewModel.useProfile(profile.id) }
                                    }
                                )
                            }
                            DetailActionButton(
                                title: AgentText.renameProfile,
                                systemImage: "pencil",
                                action: { showRenameDialog = true }
                            )
                            DetailActionButton(
                                title: AgentText.exportProfile,
                                systemImage: "square.and.arrow.up",
                                action: {
                                    Task { await viewModel.exportProfile(profile.id) }
                                }
                            )
                            if !profile.isDefault {
                                DetailActionButton(
                                    title: AgentText.deleteProfile,
                                    systemImage: "trash",
                                    style: .danger,
                                    action: { showDeleteDialog = true }
                                )
                            } else {
                                DetailActionButton(
                                    title: AgentText.defaultProfileHint,
                                    systemImage: "lock.fill",
                                    action: {}
                                )
                                .disabled(true)
                                .opacity(0.5)
                            }
                        }
                        if !profile.isDefault {
                            Text("删除将停止 gateway、移除系统服务、移除命令别名并删除所有 profile 数据。系统会要求输入 profile 名以确认。")
                                .font(.system(size: 11))
                                .foregroundColor(AgentPalette.textMuted)
                                .lineSpacing(2)
                        }
                    }
                }

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Profile Header Card

    @ViewBuilder
    private func profileHeaderCard(_ profile: AgentProfile) -> some View {
        HStack(alignment: .center, spacing: 16) {
            AgentAvatar(letter: profile.avatarLetter, isActive: profile.isActive, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(profile.displayTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(AgentPalette.textPrimary)
                    if profile.isDefault {
                        StatusPill(
                            text: "默认",
                            color: AgentPalette.textPrimary,
                            icon: "star.fill"
                        )
                    }
                    if profile.isActive {
                        StatusPill(
                            text: "当前激活",
                            color: AgentPalette.statusRunning,
                            icon: "circle.fill"
                        )
                    }
                }
                if !profile.description.isEmpty {
                    Text(profile.description)
                        .font(.system(size: 12))
                        .foregroundColor(AgentPalette.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if !profile.model.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 9))
                            Text(profile.model)
                                .font(.system(size: 10.5, design: .monospaced))
                        }
                        .foregroundColor(AgentPalette.textMuted)
                    }
                    if profile.isDistribution {
                        DistributionBadge(label: profile.distributionLabel)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AgentPalette.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AgentPalette.border, lineWidth: 0.5)
        )
    }

    // MARK: - Section Block

    @ViewBuilder
    private func sectionBlock<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentDetailSectionHeader(icon: icon, title: title)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AgentPalette.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AgentPalette.border, lineWidth: 0.5)
            )
        }
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
