import SwiftUI

/// 2D 可视化办公室：背景、装饰、办公桌、工具栏。
struct TaskBoardOfficeView: View {
    @ObservedObject var viewModel: TaskBoardViewModel
    @StateObject private var agentVM = AgentViewModel.shared

    @Binding var selectedTaskId: String?

    let onNewTask: () -> Void
    let onSwitchBoard: () -> Void
    let onNewBoard: () -> Void
    let onRefresh: () -> Void
    let onNudge: () -> Void

    @State private var officeStates: [AgentOfficeState] = []
    @State private var lastTargets: [String: PetAnimation] = [:]
    @State private var lastPhases: [String: AgentAnimationPhase] = [:]

    @State private var isRotating = false
    @State private var bounceOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                OfficeLayout.bgColor.ignoresSafeArea()

                corridorPaths(in: geo.size)

                OfficeDecorationsView(size: geo.size)

                bulletinBoard(in: geo.size)

                agentDesks(in: geo.size)

                officeToolbar

                if viewModel.model.isLoading {
                    loadingOverlay
                }
            }
        }
        .task {
            recomputeStates()
        }
        .task(id: transitionKey) {
            await monitorTransitions()
        }
        .onChange(of: viewModel.model.tasks) { _, _ in
            recomputeStates()
        }
        .onChange(of: agentVM.model.profiles) { _, _ in
            recomputeStates()
        }
    }

    private var loadingOverlay: some View {
        Color.black.opacity(0.15)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 16) {
                    Image("applogo")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(isRotating ? 360 : 0))
                        .offset(y: bounceOffset)
                        .onAppear {
                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                isRotating = true
                            }
                            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                                bounceOffset = -12
                            }
                        }
                        .onDisappear {
                            isRotating = false
                            bounceOffset = 0
                        }

                    Text("加载看板中…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(OfficePalette.textPrimary)
                }
            )
    }

    /// 用于在过渡期间持续重新评估动画状态。
    private var transitionKey: String {
        officeStates.map { state -> String in
            switch state.transition {
            case .leaving(let until, _):
                return "l:\(until.timeIntervalSinceReferenceDate)"
            case .walking(let until, _):
                return "w:\(until.timeIntervalSinceReferenceDate)"
            case .settled:
                return "s"
            case .away:
                return "a"
            }
        }.joined(separator: "|")
    }

    // MARK: - Recompute States

    private func recomputeStates() {
        let profiles = agentVM.model.profiles
        let tasks = viewModel.model.tasks

        var states: [AgentOfficeState] = []
        var newTargets: [String: PetAnimation] = [:]
        var newPhases: [String: AgentAnimationPhase] = [:]

        for profile in profiles {
            let profileTasks = tasks.filter {
                AgentOfficeState.matches(profile: profile, assignee: $0.assignee)
            }
            let previousTarget = lastTargets[profile.id]
            let previousPhase = lastPhases[profile.id] ?? .settled

            let tempState = AgentOfficeState(
                profile: profile,
                tasks: profileTasks,
                transition: previousPhase
            )
            let target = tempState.targetAnimation

            // 先解析当前 phase 是否已过期
            let resolved = resolve(previousPhase)
            let phase: AgentAnimationPhase
            if let previousTarget = previousTarget, previousTarget != target {
                phase = AgentOfficeState.phase(
                    from: previousTarget,
                    to: target,
                    previousPhase: resolved
                )
            } else {
                phase = resolved
            }

            newTargets[profile.id] = target
            newPhases[profile.id] = phase
            states.append(AgentOfficeState(
                profile: profile,
                tasks: profileTasks,
                transition: phase
            ))
        }

        lastTargets = newTargets
        lastPhases = newPhases
        officeStates = states
    }

    private func resolve(_ phase: AgentAnimationPhase) -> AgentAnimationPhase {
        switch phase {
        case .settled, .away:
            return phase
        case .leaving(let until, let next):
            return Date() < until ? phase : resolve(next)
        case .walking(let until, let next):
            return Date() < until ? phase : resolve(next)
        }
    }

    /// 在过渡期间定时刷新，确保动画阶段按时间推进。
    private func monitorTransitions() async {
        while officeStates.contains(where: { $0.isTransitioning }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
            recomputeStates()
        }
    }

    // MARK: - Bulletin Board

    private func bulletinBoard(in size: CGSize) -> some View {
        let columns = TaskBoardPageModel.kanbanColumns
        let counts = viewModel.model.tasksByStatus()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(OfficePalette.textMuted)
                Text("看板列总览")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(OfficePalette.textMuted)
            }

            HStack(spacing: 6) {
                ForEach(columns) { status in
                    VStack(spacing: 3) {
                        Text(status.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(OfficePalette.textPrimary)
                            .lineLimit(1)
                        Text("\(counts[status]?.count ?? 0)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(statusOfficeColor(status))
                    }
                    .frame(minWidth: 44)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(OfficePalette.deskShadow.opacity(0.5), lineWidth: 1)
                    )
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(OfficePalette.deskSurface.opacity(0.6))
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(OfficePalette.deskShadow, lineWidth: 1)
        )
        .position(x: size.width * 0.5, y: size.height * 0.12)
    }

    private func statusOfficeColor(_ status: TaskStatus) -> Color {
        switch status {
        case .triage:  return Color.gray
        case .todo:    return Color(red: 0.231, green: 0.510, blue: 0.965)
        case .ready:   return Color(red: 0.50, green: 0.35, blue: 0.95)
        case .running: return Color(red: 0.133, green: 0.773, blue: 0.369)
        case .blocked: return Color(red: 0.961, green: 0.620, blue: 0.043)
        case .done:    return Color(red: 0.420, green: 0.420, blue: 0.420)
        case .archived: return Color.gray
        }
    }

    // MARK: - Corridor Paths

    private func corridorPaths(in size: CGSize) -> some View {
        let positions = OfficeLayout.deskPositions(count: officeStates.count, in: size)
        guard positions.count > 1 else { return AnyView(EmptyView()) }

        return AnyView(
            Canvas { context, _ in
                let path = Path { p in
                    for (i, pos) in positions.enumerated() {
                        let y = pos.y + 50
                        if i == 0 {
                            p.move(to: CGPoint(x: pos.x - 60, y: y))
                        } else {
                            p.addLine(to: CGPoint(x: pos.x - 60, y: y))
                        }
                        p.addLine(to: CGPoint(x: pos.x + 60, y: y))
                    }
                }
                context.stroke(
                    path,
                    with: .color(OfficePalette.deskShadow.opacity(0.25)),
                    lineWidth: 8
                )
            }
        )
    }

    // MARK: - Agent Desks

    private func agentDesks(in size: CGSize) -> some View {
        let positions = OfficeLayout.deskPositions(count: officeStates.count, in: size)
        return ForEach(Array(officeStates.enumerated()), id: \.element.id) { index, state in
            AgentDeskView(
                state: state,
                onTaskTap: { selectedTaskId = $0 }
            )
            .position(positions[safe: index] ?? CGPoint(x: size.width / 2, y: size.height / 2))
        }
    }

    // MARK: - Toolbar

    private var officeToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onSwitchBoard) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(OfficePalette.textMuted)
                        Text(viewModel.model.activeBoardName.isEmpty ? "—" : viewModel.model.activeBoardName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(OfficePalette.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.7))
                    )
                    .overlay(
                        Capsule()
                            .stroke(OfficePalette.deskShadow, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                OfficeToolbarButton(title: "刷新", systemImage: "arrow.clockwise", action: onRefresh)
                OfficeToolbarButton(title: "新建任务", systemImage: "plus", isPrimary: true, action: onNewTask)

                overflowMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                OfficePalette.bgBase.opacity(0.85)
                    .overlay(
                        Rectangle()
                            .fill(OfficePalette.deskShadow.opacity(0.3))
                            .frame(height: 1),
                        alignment: .bottom
                    )
            )

            Spacer()
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button(action: onSwitchBoard) {
                Label("切换看板", systemImage: "rectangle.stack")
            }
            Button(action: onNewBoard) {
                Label("新建看板", systemImage: "rectangle.stack.badge.plus")
            }
            Button(action: onNudge) {
                Label("Nudge", systemImage: "bolt")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(OfficePalette.textPrimary)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(OfficePalette.deskShadow, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - Office Toolbar Button

private struct OfficeToolbarButton: View {
    let title: String
    let systemImage: String
    var isPrimary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: isPrimary ? .semibold : .medium))
            }
            .foregroundColor(isPrimary ? OfficePalette.bgBase : OfficePalette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isPrimary ? OfficePalette.textPrimary : Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(OfficePalette.deskShadow, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Decorations

private struct OfficeDecorationsView: View {
    let size: CGSize

    var body: some View {
        ForEach(OfficeLayout.decorations(in: size)) { decoration in
            Image(decoration.imageName)
                .resizable()
                .interpolation(.high)
                .frame(width: decoration.size.width, height: decoration.size.height)
                .position(decoration.position)
        }
    }
}

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
