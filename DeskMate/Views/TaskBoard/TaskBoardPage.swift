import SwiftUI
import Combine

/// 任务看板主页 — 一比一还原 Flutter `TaskBoardPage`（StatefulWidget）。
///
/// MVVM：
/// - ViewModel: `TaskBoardViewModel`
/// - View: 本 SwiftUI 视图
/// - Model: `TaskBoardModel.swift`
struct TaskBoardPage: View {

    // MARK: - State

    @StateObject private var viewModel: TaskBoardViewModel

    /// 对话框可见性
    @State private var showNewTaskDialog: Bool = false
    @State private var showSwitchBoardDialog: Bool = false
    @State private var showNewBoardDialog: Bool = false

    /// 真实技能列表(从 SkillScannerService 扫描)
    @State private var availableSkills: [TBSkillItem] = []

    // MARK: - Init

    init(availableSkills: [TBSkillItem] = []) {
        self.availableSkills = availableSkills
        _viewModel = StateObject(wrappedValue: TaskBoardViewModel())
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            mainContent
            TBToastOverlay()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TBPalette.bgBase)
        .sheet(isPresented: $showNewTaskDialog) {
            TBNewTaskDialog(
                viewModel: viewModel,
                availableSkills: availableSkills
            )
        }
        .sheet(isPresented: $showSwitchBoardDialog) {
            TBSwitchBoardDialog(
                boards: viewModel.model.boards,
                activeBoardId: viewModel.model.activeBoardId,
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $showNewBoardDialog) {
            TBNewBoardDialog(viewModel: viewModel)
        }
        // ---- 键盘快捷键 ----
        // ⌘N: 新建任务
        .keyboardShortcut("n", modifiers: .command)
        // ⌘B: 切换看板
        .background(
            Button("") { showSwitchBoardDialog = true }
                .keyboardShortcut("b", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        // ⌘R: 刷新
        .background(
            Button("") { Task { await viewModel.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        // ⌘. : Nudge 调度
        .background(
            Button("") { Task { await viewModel.nudgeDispatcher() } }
                .keyboardShortcut(".", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        // ⌘⇧N: 新建看板
        .background(
            Button("") { showNewBoardDialog = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        // ESC: 清除筛选
        .background(
            Button("") { viewModel.clearFilter() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .task {
            // 启动时拉取真实技能列表
            let vm = viewModel
            let skills = await vm.loadAvailableSkills()
            await MainActor.run {
                self.availableSkills = skills
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 错误条
            if let err = viewModel.model.errorMessage, !err.isEmpty {
                TBErrorBanner(message: err) {
                    Task { await viewModel.refresh() }
                }
            }

            // 加载中
            if viewModel.model.isLoading {
                TBLoadingView(title: TBText.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        TBHeaderRow(
                            model: viewModel.model,
                            onSwitchBoard: { showSwitchBoardDialog = true },
                            onNewTask: { showNewTaskDialog = true },
                            onNewBoard: { showNewBoardDialog = true },
                            onRefresh: {
                                Task { await viewModel.refresh() }
                            },
                            onNudge: {
                                Task { await viewModel.nudgeDispatcher() }
                            }
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        // Subtitle
                        Text(TBText.pageSubtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(TBPalette.textMuted)
                            .padding(.horizontal, 24)

                        // Filter bar
                        TBFilterBar(
                            filter: viewModel.model.filter,
                            onFilterChange: { f in viewModel.setFilter(f) },
                            onClear: { viewModel.clearFilter() }
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 4)

                        // Kanban columns
                        TBKanbanColumns(model: viewModel.model, viewModel: viewModel)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                    }
                }
            }
        }
    }
}
