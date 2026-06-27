import SwiftUI
import AppKit

// MARK: - Header Row

/// 顶部 Header 行：标题 + 当前看板 + 切换/新建/触发按钮。
struct TBHeaderRow: View {
    let model: TaskBoardPageModel
    let onSwitchBoard: () -> Void
    let onNewTask: () -> Void
    let onNewBoard: () -> Void
    let onRefresh: () -> Void
    let onNudge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(TBText.pageTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(TBPalette.textPrimary)
                        // 当前看板 pill
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(TBPalette.textMuted)
                            Text(model.activeBoardName.isEmpty ? "—" : model.activeBoardName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TBPalette.textPrimary)
                                .lineLimit(1)
                            if !model.persistedActiveSlug.isEmpty {
                                Text("·")
                                    .font(.system(size: 11))
                                    .foregroundColor(TBPalette.textMuted)
                                Text(model.persistedActiveSlug)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(TBPalette.textMuted)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(TBPalette.bgElevated)
                        )
                        .overlay(
                            Capsule().stroke(TBPalette.border, lineWidth: 1)
                        )
                    }
                    HStack(spacing: 12) {
                        Text(TBText.pageSubtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(TBPalette.textMuted)
                        // 任务总数
                        Text("\(model.tasks.count) 个任务")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(TBPalette.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(TBPalette.countBg)
                            )
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    // 刷新
                    TBGhostButton(
                        title: TBText.refresh,
                        systemImage: "arrow.clockwise",
                        action: onRefresh
                    )
                    // Nudge 按钮(立即触发 dispatcher)
                    TBGhostButton(
                        title: TBText.nudge,
                        systemImage: "bolt",
                        action: onNudge
                    )
                    // 切换看板
                    TBGhostButton(
                        title: TBText.switchBoard,
                        systemImage: nil,
                        action: onSwitchBoard
                    )
                    // 新建看板
                    TBGhostButton(
                        title: TBText.newBoard,
                        systemImage: "rectangle.stack.badge.plus",
                        action: onNewBoard
                    )
                    // 新建任务（实心）
                    TBPrimaryButton(
                        title: TBText.newTask,
                        systemImage: "plus",
                        action: onNewTask
                    )
                }
            }
        }
    }
}

// MARK: - Ghost Button

/// 描边按钮 — 对应 Flutter `GestureDetector` 包裹的 outline 容器。
struct TBGhostButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(TBPalette.textDisabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TBPalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary Button

/// 主按钮（白底深色文字）— 对齐 Flutter 新建任务按钮。
struct TBPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(TBPalette.inverseInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(TBPalette.inverse)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Bar

/// 顶部筛选条(search / tenant / assignee) — 对齐官方 `kanban_list` 过滤栏。
struct TBFilterBar: View {
    let filter: TaskBoardFilter
    let onFilterChange: (TaskBoardFilter) -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(TBPalette.textMuted)
                TextField("搜索标题 / 描述…", text: Binding(
                    get: { filter.searchKeyword },
                    set: { onFilterChange(TaskBoardFilter(
                        searchKeyword: $0,
                        tenant: filter.tenant,
                        assignee: filter.assignee
                    )) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(TBPalette.textPrimary)
                if !filter.searchKeyword.isEmpty {
                    Button {
                        onFilterChange(TaskBoardFilter(
                            searchKeyword: "",
                            tenant: filter.tenant,
                            assignee: filter.assignee
                        ))
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(TBPalette.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: 280)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(TBPalette.inputBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TBPalette.border, lineWidth: 1)
            )

            // Tenant
            TBPillInput(
                placeholder: "Tenant",
                text: Binding(
                    get: { filter.tenant },
                    set: { onFilterChange(TaskBoardFilter(
                        searchKeyword: filter.searchKeyword,
                        tenant: $0,
                        assignee: filter.assignee
                    )) }
                )
            )
            .frame(width: 120)

            // Assignee
            TBPillInput(
                placeholder: "Assignee",
                text: Binding(
                    get: { filter.assignee },
                    set: { onFilterChange(TaskBoardFilter(
                        searchKeyword: filter.searchKeyword,
                        tenant: filter.tenant,
                        assignee: $0
                    )) }
                )
            )
            .frame(width: 140)

            Spacer()

            // Lanes by profile 开关
            if filter.isActive {
                TBGhostButton(title: "清除筛选", systemImage: "xmark", action: onClear)
            }
        }
    }
}

/// 圆角输入小框(用于筛选)。
struct TBPillInput: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(TBPalette.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TBPalette.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TBPalette.inputBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TBPalette.border, lineWidth: 1)
        )
    }
}

// MARK: - Kanban Columns Container

/// 6 列 Kanban 容器 — 对齐官方:Triage / Todo / Ready / Running / Blocked / Done。
struct TBKanbanColumns: View {
    let model: TaskBoardPageModel
    @ObservedObject var viewModel: TaskBoardViewModel

    var body: some View {
        let grouped = model.tasksByStatus()
        let columns = TaskBoardPageModel.kanbanColumns
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.element) { _, status in
                TBKanbanColumn(
                    title: columnLabel(status),
                    count: grouped[status]?.count ?? 0,
                    status: status,
                    tasks: grouped[status] ?? [],
                    model: model,
                    viewModel: viewModel
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 列标题本地化（与 Flutter `_columnLabel` 一致）— 复用 TBText 静态文案。
    private func columnLabel(_ status: TaskStatus) -> String {
        switch status {
        case .triage:   return TBText.columnTriage
        case .todo:     return TBText.columnTodo
        case .ready:    return TBText.columnReady
        case .running:  return TBText.columnInProgress
        case .blocked:  return TBText.columnBlocked
        case .done:     return TBText.columnDone
        default:        return status.label
        }
    }
}

// MARK: - Single Kanban Column

/// 单列 Kanban — 对齐 Flutter `_KanbanColumn`。
/// Running 列支持 "Lanes by profile" 分组。
struct TBKanbanColumn: View {
    let title: String
    let count: Int
    let status: TaskStatus
    let tasks: [TaskItem]
    let model: TaskBoardPageModel
    @ObservedObject var viewModel: TaskBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack(spacing: 6) {
                // 状态指示点(脉冲表示 running 列有活跃任务)
                if status == .running, !tasks.isEmpty {
                    TBStatusDot(color: TBPalette.statusStart, pulse: true)
                } else if status == .blocked, !tasks.isEmpty {
                    TBStatusDot(color: TBPalette.statusBlock)
                } else if status == .done, !tasks.isEmpty {
                    TBStatusDot(color: TBPalette.statusComplete)
                } else if status == .triage, !tasks.isEmpty {
                    TBStatusDot(color: TBPalette.textDisabled)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TBPalette.textPrimary)
                // 数字动画
                Text("\(count)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(TBPalette.textMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(TBPalette.countBg)
                    )
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.easeInOut(duration: 0.22), value: count)
                Spacer()
                // Running 列:显示 Lanes by profile 开关
                if status == .running {
                    Button {
                        viewModel.setLanesByProfile(!model.lanesByProfile)
                    } label: {
                        Image(systemName: model.lanesByProfile
                              ? "rectangle.split.3x1.fill"
                              : "rectangle.split.3x1")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(model.lanesByProfile
                                             ? TBPalette.inverse
                                             : TBPalette.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help(model.lanesByProfile
                          ? "Lanes by profile: ON"
                          : "Lanes by profile: OFF")
                }
            }

            if !tasks.isEmpty {
                if status == .running && model.lanesByProfile {
                    // 按 profile 分组
                    ForEach(Array(profileGroups(tasks).enumerated()), id: \.element.0) { idx, group in
                        TBLaneSection(
                            label: profileDisplayName(group.0),
                            tasks: group.1,
                            viewModel: viewModel,
                            status: status
                        )
                        .padding(.top, idx == 0 ? 12 : 8)
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(tasks) { task in
                            TBTaskCard(task: task, viewModel: viewModel, status: status)
                        }
                    }
                    .padding(.top, 12)
                }
            } else {
                // 空态 — 用统一空态组件
                TBEmptyHint(text: emptyHint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(TBPalette.columnBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(TBPalette.border, lineWidth: 1)
        )
    }

    private var emptyHint: String {
        switch status {
        case .triage:  return "暂无待分类任务"
        case .todo:    return TBText.empty
        case .ready:   return "暂无待执行任务"
        case .running: return "暂无运行中任务"
        case .blocked: return "暂无阻塞任务"
        case .done:    return "暂无已完成任务"
        default:       return TBText.empty
        }
    }

    private func profileGroups(_ tasks: [TaskItem]) -> [(String, [TaskItem])] {
        let grouped = Dictionary(grouping: tasks, by: { $0.assignee.isEmpty ? "_unassigned" : $0.assignee })
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func profileDisplayName(_ key: String) -> String {
        if key == "_unassigned" { return "Unassigned" }
        return key
    }
}

// MARK: - Lane Section (Profile group)

/// Running 列里按 profile 分组的泳道块。
struct TBLaneSection: View {
    let label: String
    let tasks: [TaskItem]
    @ObservedObject var viewModel: TaskBoardViewModel
    let status: TaskStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(TBPalette.textMuted)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(TBPalette.textHeader)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Text("· \(tasks.count)")
                    .font(.system(size: 10))
                    .foregroundColor(TBPalette.textMuted)
            }
            ForEach(tasks) { task in
                TBTaskCard(task: task, viewModel: viewModel, status: status)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TBPalette.bgBase.opacity(0.5))
        )
    }
}

// MARK: - Task Card

/// 任务卡片 — 对齐 Flutter `_TaskCard`。
/// Triage 任务显示"分解 / Specify"两个快速操作。
struct TBTaskCard: View {
    let task: TaskItem
    @ObservedObject var viewModel: TaskBoardViewModel
    var status: TaskStatus = .todo
    @State private var showDetail: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TBPalette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                // Tags row
                HStack(spacing: 6) {
                    if !task.priority.isEmpty, task.status != .done {
                        TBPill(text: task.priority)
                    }
                    if !task.parentIds.isEmpty {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                            .foregroundColor(TBPalette.textMuted)
                            .help("Parent: \(task.parentIds.joined(separator: ", "))")
                    }
                    if task.status == .blocked, !task.comments.isEmpty {
                        Image(systemName: "message")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(TBPalette.textMuted)
                    }
                    if !task.runHistory.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9))
                            Text("\(task.runHistory.count)")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(TBPalette.textMuted)
                        .help("\(task.runHistory.count) 次运行")
                    }
                    Spacer(minLength: 0)
                    Text(
                        task.status == .done
                            ? task.assignee
                            : (task.assignee.isEmpty ? TBText.unassigned : task.assignee)
                    )
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(TBPalette.textMuted)
                    .lineLimit(1)
                }

                // Triage 任务快捷操作
                if status == .triage && isHovered {
                    HStack(spacing: 6) {
                        TBTriageActionButton(
                            title: TBText.decompose,
                            systemImage: "scissors",
                            color: TBPalette.statusStart,
                            action: {
                                Task { await viewModel.decomposeTask(task.id) }
                            }
                        )
                        TBTriageActionButton(
                            title: TBText.specify,
                            systemImage: "arrow.right",
                            color: TBPalette.statusComplete,
                            action: {
                                Task { await viewModel.specifyTask(task.id) }
                            }
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(TBPalette.cardBgAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHovered ? TBPalette.textDisabled.opacity(0.5) : TBPalette.border,
                        lineWidth: 1
                    )
            )
            // hover 时轻微抬升 + 阴影
            .shadow(
                color: Color.black.opacity(isHovered ? 0.4 : 0),
                radius: isHovered ? 6 : 0,
                x: 0,
                y: isHovered ? 2 : 0
            )
            .scaleEffect(isHovered ? 1.012 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .sheet(isPresented: $showDetail) {
            TBTaskDetailPopup(taskId: task.id, viewModel: viewModel)
        }
    }
}

// MARK: - Triage Action Button

/// Triage 卡片上显示的快捷操作按钮(在 hover 时显示)。
struct TBTriageActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pill (Priority tag)

/// 优先级 / 状态小标签 — 对齐 Flutter 卡片里的 tag 容器。
struct TBPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(TBPalette.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(TBPalette.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(TBPalette.border, lineWidth: 1)
            )
    }
}

// MARK: - Task Detail Popup

/// 任务详情弹窗(点击卡片触发)。
/// - Run History:来自 `kanban runs <id>`
/// - 父子链接:显示 parent / child 任务
/// - 评论输入:TextField + Add 按钮
/// - Summary + metadata:用于 `complete` 任务的 handoff
struct TBTaskDetailPopup: View {
    let taskId: String
    @ObservedObject var viewModel: TaskBoardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newComment: String = ""
    @State private var summary: String = ""
    @State private var metadataText: String = ""
    @State private var blockReason: String = ""
    @State private var showBlockInput: Bool = false
    @State private var showCompleteInput: Bool = false
    @State private var hasLoadedRuns: Bool = false

    private var task: TaskItem? {
        viewModel.model.tasks.first(where: { $0.id == taskId })
    }

    var body: some View {
        Group {
            if let task = task {
                content(task: task)
            } else {
                TBEmptyView(icon: "questionmark.circle", title: "任务已不存在")
            }
        }
        .frame(width: 520, height: 620)
        .background(TBPalette.bgBase)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(TBPalette.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func content(task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TBPill(text: task.status.label)
                    if !task.priority.isEmpty {
                        TBPill(text: task.priority)
                    }
                    Spacer()
                    Text(task.id)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(TBPalette.textMuted)
                        .lineLimit(1)
                }
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(TBPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !task.body.isEmpty {
                    Text(task.body)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(TBPalette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(TBPalette.bgBase)

            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)

            // Content (scrollable)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 基础信息
                    detailGroup {
                        TBDetailRow(label: TBText.statusLabel, value: task.status.label)
                        TBDetailRow(label: TBText.priorityLabel, value: task.priority.isEmpty ? "—" : task.priority)
                        TBDetailRow(
                            label: TBText.assigneeLabel,
                            value: task.assignee.isEmpty ? "—" : task.assignee
                        )
                        if !task.workspace.isEmpty {
                            TBDetailRow(label: TBText.workspace, value: task.workspace)
                        }
                        if !task.tenant.isEmpty {
                            TBDetailRow(label: TBText.tenant, value: task.tenant)
                        }
                    }

                    // Summary / metadata(完成时填的)
                    if !task.summary.isEmpty || !task.metadata.isEmpty {
                        detailGroup {
                            if !task.summary.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Summary")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(TBPalette.textHeader)
                                    Text(task.summary)
                                        .font(.system(size: 12))
                                        .foregroundColor(TBPalette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if !task.metadata.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Metadata")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(TBPalette.textHeader)
                                    ForEach(Array(task.metadata.sorted(by: { $0.key < $1.key })), id: \.key) { kv in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text(kv.key)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(TBPalette.textMuted)
                                            Text(kv.value)
                                                .font(.system(size: 11))
                                                .foregroundColor(TBPalette.textPrimary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 父子任务
                    if !task.parentIds.isEmpty {
                        detailGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(TBText.parentTasks)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(TBPalette.textHeader)
                                ForEach(task.parentIds, id: \.self) { pid in
                                    parentLinkButton(id: pid)
                                }
                            }
                        }
                    }
                    let childIds = viewModel.model.tasks
                        .filter { $0.parentIds.contains(task.id) }
                        .map { $0.id }
                    if !childIds.isEmpty {
                        detailGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(TBText.childTasks)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(TBPalette.textHeader)
                                ForEach(childIds, id: \.self) { cid in
                                    parentLinkButton(id: cid)
                                }
                            }
                        }
                    }

                    // Run History
                    if !task.runHistory.isEmpty {
                        detailGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                TBSectionTitle(
                                    text: TBText.runHistory,
                                    trailing: "\(task.runHistory.count) 次"
                                )
                                ForEach(task.runHistory) { run in
                                    TBTaskRunRow(run: run)
                                }
                            }
                        }
                    }

                    // 评论
                    detailGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            TBSectionTitle(
                                text: TBText.commentsLabel,
                                trailing: "\(task.comments.count) 条"
                            )
                            if !task.comments.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(task.comments) { c in
                                        TBCommentRow(comment: c)
                                    }
                                }
                            }
                            HStack(spacing: 8) {
                                TextField("添加评论…", text: $newComment)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundColor(TBPalette.textPrimary)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(TBPalette.inputBg)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(TBPalette.border, lineWidth: 1)
                                    )
                                    .onSubmit { submitComment() }
                                Button(TBText.addComment) { submitComment() }
                                    .buttonStyle(TBStatusButtonStyle(color: TBPalette.textMuted))
                                    .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)

            // Footer
            footer(task: task)
        }
        .background(TBPalette.bgBase)
        .onAppear {
            summary = task.summary
            metadataText = task.metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "\n")
            if !hasLoadedRuns {
                hasLoadedRuns = true
                Task { await viewModel.loadTaskRuns(taskId) }
            }
        }
    }

    @ViewBuilder
    private func detailGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TBPalette.columnBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(TBPalette.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func parentLinkButton(id: String) -> some View {
        let linkedTask = viewModel.model.tasks.first(where: { $0.id == id })
        Button {
            // 切换到该任务详情(关闭当前弹窗,再打开)
            // 简化:此处只做打开新弹窗;实际应用中可切换 sheet
            TBToast.show("跳转至任务 \(id)")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 9))
                Text(linkedTask?.title ?? id)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundColor(TBPalette.textPrimary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func footer(task: TaskItem) -> some View {
        VStack(spacing: 0) {
            // Block 输入框
            if showBlockInput {
                HStack(spacing: 8) {
                    TextField("阻塞原因…", text: $blockReason)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(TBPalette.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(TBPalette.inputBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(TBPalette.border, lineWidth: 1)
                        )
                        .onSubmit { submitBlock() }
                    Button("确定") { submitBlock() }
                        .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusBlock))
                        .disabled(blockReason.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("取消") {
                        showBlockInput = false
                        blockReason = ""
                    }
                    .buttonStyle(TBStatusButtonStyle(color: TBPalette.textMuted))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            // Complete 输入框
            if showCompleteInput {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Summary (closeout)…", text: $summary, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(TBPalette.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 50, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(TBPalette.inputBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(TBPalette.border, lineWidth: 1)
                        )
                    TextField("Metadata (key=value 每行一个, 可选)", text: $metadataText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(TBPalette.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 50, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(TBPalette.inputBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(TBPalette.border, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            // Action toolbar
            HStack(spacing: 8) {
                if task.isActive {
                    if task.status != .done {
                        if showCompleteInput {
                            Button("提交完成") { submitComplete() }
                                .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusComplete))
                                .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty)
                        } else {
                            Button(TBText.completeAction) {
                                showCompleteInput = true
                                showBlockInput = false
                            }
                            .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusComplete))
                        }
                    }
                    if task.status == .triage {
                        Button(TBText.decompose) {
                            Task { await viewModel.decomposeTask(task.id) }
                            dismiss()
                        }
                        .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusStart))
                        Button(TBText.specify) {
                            Task { await viewModel.specifyTask(task.id) }
                            dismiss()
                        }
                        .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusComplete))
                    }
                    // 官方 Hermes Kanban CLI 没有 `move` verb,running 由 dispatcher
                    // claim 后自动进入,UI 不暴露手动"开始"入口(原 Start 按钮已移除)。
                    if task.status != .blocked {
                        if showBlockInput {
                            // 已在上面显示
                        } else {
                            Button(TBText.blockAction) {
                                showBlockInput = true
                                showCompleteInput = false
                            }
                            .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusBlock))
                        }
                    } else {
                        Button(TBText.unblockAction) {
                            viewModel.unblockTask(task.id)
                            dismiss()
                        }
                        .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusComplete))
                    }
                }
                Button(TBText.deleteAction) {
                    viewModel.deleteTask(task.id)
                    dismiss()
                }
                .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusDanger))

                Spacer()

                Button(TBText.close) { dismiss() }
                    .buttonStyle(TBStatusButtonStyle(color: TBPalette.textMuted))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(TBPalette.bgBase)
        }
    }

    private func submitComment() {
        let trimmed = newComment.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        viewModel.addComment(taskId, body: trimmed)
        newComment = ""
    }

    private func submitBlock() {
        let trimmed = blockReason.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        viewModel.blockTask(taskId, reason: trimmed)
        showBlockInput = false
        blockReason = ""
        dismiss()
    }

    private func submitComplete() {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespaces)
        guard !trimmedSummary.isEmpty else { return }
        // 解析 metadata key=value
        var md: [String: String] = [:]
        for line in metadataText.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let k = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let v = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if !k.isEmpty { md[k] = v }
            }
        }
        viewModel.completeTask(taskId, summary: trimmedSummary, metadata: md)
        showCompleteInput = false
        summary = ""
        metadataText = ""
        dismiss()
    }
}

// MARK: - Task Run Row

/// 任务运行记录行 — 对齐官方 Run History 段。
struct TBTaskRunRow: View {
    let run: TaskRun

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(outcomeColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(run.outcome)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(outcomeColor)
                    if !run.profile.isEmpty {
                        Text("· \(run.profile)")
                            .font(.system(size: 10))
                            .foregroundColor(TBPalette.textMuted)
                    }
                    if run.elapsed > 0 {
                        Text("· \(String(format: "%.1fs", run.elapsed))")
                            .font(.system(size: 10))
                            .foregroundColor(TBPalette.textMuted)
                    }
                    Spacer()
                    Text(run.started, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(TBPalette.textMuted)
                }
                if !run.error.isEmpty {
                    Text(run.error)
                        .font(.system(size: 10))
                        .foregroundColor(TBPalette.statusBlock)
                        .lineLimit(2)
                }
                if !run.summary.isEmpty {
                    Text(run.summary)
                        .font(.system(size: 10))
                        .foregroundColor(TBPalette.textMuted)
                        .lineLimit(3)
                }
            }
        }
    }

    private var outcomeColor: Color {
        switch run.outcome {
        case "completed":   return TBPalette.statusComplete
        case "gave_up":     return TBPalette.statusDanger
        case "spawn_failed": return TBPalette.statusDanger
        case "timed_out":   return TBPalette.statusBlock
        default:            return TBPalette.textMuted
        }
    }

    private var iconName: String {
        switch run.outcome {
        case "completed":   return "checkmark.circle.fill"
        case "gave_up":     return "xmark.circle.fill"
        case "spawn_failed": return "exclamationmark.triangle.fill"
        case "timed_out":   return "clock.badge.exclamationmark.fill"
        default:            return "circle.fill"
        }
    }
}

// MARK: - Comment Row

/// 评论行 — 头像 + 作者 + 内容。
struct TBCommentRow: View {
    let comment: TaskComment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(TBPalette.countBg)
                .frame(width: 22, height: 22)
                .overlay(
                    Text(initial)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(TBPalette.textPrimary)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(comment.author)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TBPalette.textPrimary)
                    Text(comment.createdAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(TBPalette.textMuted)
                }
                Text(comment.body)
                    .font(.system(size: 12))
                    .foregroundColor(TBPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var initial: String {
        let s = comment.author.prefix(1)
        return s.isEmpty ? "?" : String(s).uppercased()
    }
}

// MARK: - Detail Row

/// 详情弹窗里的 label / value 行 — 对齐 Flutter `_DetailRow`。
struct TBDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TBPalette.textPrimary)
                .frame(width: 80, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(TBPalette.textMuted)
            Spacer()
        }
    }
}

// MARK: - Status Button Style

/// 详情弹窗底部状态按钮的统一样式 — 与 Flutter 端 TextButton 颜色保持一致。
struct TBStatusButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed
                          ? color.opacity(0.15)
                          : Color.clear)
            )
    }
}

// MARK: - Loading / Empty

/// 加载视图 — 对齐 Flutter 的 ProgressView + "加载中…"。
struct TBLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .colorScheme(.dark)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(TBPalette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 空视图 — 对齐 Flutter 暂无数据占位。
struct TBEmptyView: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(TBPalette.textMuted)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(TBPalette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error Banner

/// 顶部错误条 — 对齐 Flutter `errorMessage` 时的提示。
struct TBErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(TBPalette.statusBlock)
            Text(message)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(TBPalette.textPrimary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(TBPalette.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(TBPalette.bgBase)
        .overlay(
            Rectangle()
                .fill(TBPalette.statusBlock)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Flow Layout

/// 简单流式布局(用于 chip 排列)。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var runSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + runSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxRowWidth = max(maxRowWidth, x)
        }
        return CGSize(width: min(maxRowWidth, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                y += rowHeight + runSpacing
                x = bounds.minX
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
