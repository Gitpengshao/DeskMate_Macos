import SwiftUI

/// 单个 agent 办公桌：桌子、精灵动画、姓名、状态徽标、任务计数、当前 running 任务。
struct AgentDeskView: View {
    let state: AgentOfficeState
    let onTaskTap: (String) -> Void

    private let spriteSize: CGFloat = 90
    private let deskWidth: CGFloat = 140
    private let deskTopHeight: CGFloat = 22

    @State private var isHovered = false

    var body: some View {
        ZStack {
            agentSprite
            desk
            statusDot
            nameLabel
            taskBadges

            if let task = state.runningTask {
                runningTaskPill(task: task)
                    .offset(y: -84)
            }

            if isHovered {
                hoverCard
                    .offset(y: -120)
            }
        }
        .frame(width: OfficeLayout.deskSize.width, height: OfficeLayout.deskSize.height)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Sprite

    private var agentSprite: some View {
        SpriteFrameAnimationView(
            config: state.currentAnimation.config,
            fps: state.currentAnimation == .walk ? 18 : 12,
            displaySize: spriteSize
        )
        .offset(y: -28)
        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
    }

    // MARK: - Desk

    private var desk: some View {
        ZStack {
            // Legs
            HStack(spacing: deskWidth - 32) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(OfficePalette.deskLegs)
                    .frame(width: 12, height: 64)
                RoundedRectangle(cornerRadius: 3)
                    .fill(OfficePalette.deskLegs)
                    .frame(width: 12, height: 64)
            }
            .offset(y: 42)

            // Top
            RoundedRectangle(cornerRadius: 6)
                .fill(OfficePalette.deskSurface)
                .frame(width: deskWidth, height: deskTopHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(OfficePalette.deskShadow, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 3)
                .offset(y: 38)
        }
    }

    // MARK: - Labels

    private var nameLabel: some View {
        Text(state.profile.displayTitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(OfficePalette.textPrimary)
            .lineLimit(1)
            .offset(y: 92)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
            )
            .offset(x: deskWidth / 2 - 8, y: 26)
    }

    private var statusColor: Color {
        switch state.currentAnimation {
        case .workAtDesk: return OfficePalette.statusWork
        case .idle:       return OfficePalette.statusIdle
        case .leave:      return OfficePalette.statusLeave
        case .walk:       return OfficePalette.statusWalk
        default:          return OfficePalette.statusLeave
        }
    }

    // MARK: - Task Badges

    private var taskBadges: some View {
        HStack(spacing: 6) {
            badge(for: .todo, label: "待办")
            badge(for: .ready, label: "就绪")
            badge(for: .running, label: "进行中")
            badge(for: .blocked, label: "阻塞")
            badge(for: .done, label: "完成")
        }
        .offset(y: 116)
    }

    private func badge(for status: TaskStatus, label: String) -> some View {
        let count = state.taskCounts[status] ?? 0
        return Group {
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .padding(.horizontal, 4)
                    .background(
                        Capsule()
                            .fill(badgeColor(for: status))
                    )
            }
        }
    }

    private func badgeColor(for status: TaskStatus) -> Color {
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

    // MARK: - Running Task

    private func runningTaskPill(task: TaskItem) -> some View {
        Button {
            onTaskTap(task.id)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(OfficePalette.statusWork)
                    .frame(width: 6, height: 6)
                Text(task.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(OfficePalette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .overlay(
                        Capsule()
                            .stroke(OfficePalette.deskShadow, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hover Status Card

    private var hoverCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.profile.displayTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(OfficePalette.textPrimary)
                .lineLimit(1)

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(stateLabel)
                    .font(.system(size: 11))
                    .foregroundColor(OfficePalette.textPrimary)
            }

            Text("Gateway: \(state.profile.gatewayStatus.label)")
                .font(.system(size: 10))
                .foregroundColor(OfficePalette.textMuted)

            if let task = state.runningTask {
                Text("进行中：\(task.title)")
                    .font(.system(size: 10))
                    .foregroundColor(OfficePalette.textPrimary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                countPill(status: .todo, label: "待办")
                countPill(status: .ready, label: "就绪")
                countPill(status: .running, label: "进行中")
                countPill(status: .blocked, label: "阻塞")
                countPill(status: .done, label: "完成")
            }
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.95))
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(OfficePalette.deskShadow, lineWidth: 1)
        )
    }

    private var stateLabel: String {
        if state.isWalking { return "移动中" }
        switch state.targetAnimation {
        case .workAtDesk: return "工作中"
        case .idle:       return "空闲"
        case .leave:      return "离线"
        case .walk:       return "移动中"
        default:          return "未知"
        }
    }

    private func countPill(status: TaskStatus, label: String) -> some View {
        let count = state.taskCounts[status] ?? 0
        return Text("\(label) \(count)")
            .font(.system(size: 9))
            .foregroundColor(OfficePalette.textMuted)
            .lineLimit(1)
    }
}
