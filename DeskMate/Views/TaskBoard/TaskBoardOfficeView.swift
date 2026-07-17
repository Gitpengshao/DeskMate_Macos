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
    @State private var lastTransitions: [String: AgentAnimationPhase] = [:]

    @State private var isRotating = false
    @State private var bounceOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                OfficeLayout.bgColor.ignoresSafeArea()

                OfficeDecorationsView(size: geo.size)

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
        .task(id: walkTransitionKey) {
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

    /// 用于在 walk 过渡期间持续重新评估动画状态。
    private var walkTransitionKey: String {
        officeStates.map { state -> String in
            switch state.transition {
            case .walking(let until):
                return "w:\(until.timeIntervalSinceReferenceDate)"
            case .settled:
                return "s"
            }
        }.joined(separator: "|")
    }

    // MARK: - Recompute States

    private func recomputeStates() {
        let profiles = agentVM.model.profiles
        let tasks = viewModel.model.tasks

        var states: [AgentOfficeState] = []
        var newTargets: [String: PetAnimation] = [:]
        var newTransitions: [String: AgentAnimationPhase] = [:]

        for profile in profiles {
            let profileTasks = tasks.filter {
                AgentOfficeState.matches(profile: profile, assignee: $0.assignee)
            }
            let previousTarget = lastTargets[profile.id]
            let previousTransition = lastTransitions[profile.id] ?? .settled

            let tempState = AgentOfficeState(
                profile: profile,
                tasks: profileTasks,
                transition: previousTransition
            )
            let target = tempState.targetAnimation

            let transition: AgentAnimationPhase
            if let previousTarget, previousTarget != target {
                transition = .walking(until: Date().addingTimeInterval(0.8))
            } else {
                switch previousTransition {
                case .walking(let until):
                    transition = Date() < until ? previousTransition : .settled
                case .settled:
                    transition = .settled
                }
            }

            newTargets[profile.id] = target
            newTransitions[profile.id] = transition
            states.append(AgentOfficeState(
                profile: profile,
                tasks: profileTasks,
                transition: transition
            ))
        }

        lastTargets = newTargets
        lastTransitions = newTransitions
        officeStates = states
    }

    /// 在 walk 过渡期间定时刷新，确保过渡结束后切回目标动画。
    private func monitorTransitions() async {
        while officeStates.contains(where: { $0.isWalking }) {
            try? await Task.sleep(nanoseconds: 100_000_000)
            recomputeStates()
        }
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
