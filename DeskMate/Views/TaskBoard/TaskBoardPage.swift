import SwiftUI
import Combine

/// 任务看板主页：2D 办公室视角查看 Hermes Kanban 任务进度。
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

    /// 当前选中的任务 id（用于从办公桌打开详情弹窗）
    @State private var selectedTaskId: String? = nil

    // MARK: - Init

    init() {
        _viewModel = StateObject(wrappedValue: TaskBoardViewModel())
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            mainContent
            TBToastOverlay()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OfficeLayout.bgColor)
        .sheet(isPresented: $showNewTaskDialog) {
            TBNewTaskDialog(viewModel: viewModel)
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
        .sheet(isPresented: Binding(
            get: { selectedTaskId != nil },
            set: { if !$0 { selectedTaskId = nil } }
        )) {
            if let taskId = selectedTaskId,
               let task = viewModel.model.tasks.first(where: { $0.id == taskId }) {
                TBTaskDetailPopup(task: task, viewModel: viewModel)
                    .task {
                        await viewModel.loadTaskDetail(taskId)
                    }
            }
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
        // ⌘⇧N: 新建看板
        .background(
            Button("") { showNewBoardDialog = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            TaskBoardOfficeView(
                viewModel: viewModel,
                selectedTaskId: $selectedTaskId,
                onNewTask: { showNewTaskDialog = true },
                onSwitchBoard: { showSwitchBoardDialog = true },
                onNewBoard: { showNewBoardDialog = true },
                onRefresh: {
                    Task { await viewModel.refresh() }
                },
                onNudge: {
                    Task { await viewModel.nudgeDispatcher() }
                }
            )

            // 错误条
            if let err = viewModel.model.errorMessage, !err.isEmpty {
                VStack {
                    TBErrorBanner(message: err)
                    Spacer()
                }
            }
        }
    }
}
