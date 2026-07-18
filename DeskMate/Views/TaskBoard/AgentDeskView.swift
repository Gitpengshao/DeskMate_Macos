import SwiftUI

/// 单个 agent 办公桌：桌子、精灵动画、任务文档卡片、姓名、状态徽标。
struct AgentDeskView: View {
    let state: AgentOfficeState
    let onTaskTap: (String) -> Void

    private let spriteSize: CGFloat = 90
    private let deskWidth: CGFloat = 140
    private let deskTopHeight: CGFloat = 22

    @State private var isHovered = false

    var body: some View {
        ZStack {
            if state.isAgentPresent {
                agentSprite
            } else {
                awayIndicator
            }

            desk

            if state.isAgentPresent {
                documentCards
            }

            statusDot
            nameLabel

            if isHovered {
                hoverCard
                    .offset(y: -128)
            }
        }
        .frame(width: OfficeLayout.deskSize.width, height: OfficeLayout.deskSize.height)
        .contentShape(Rectangle())
        .onTapGesture {
            if let task = state.runningTask ?? state.blockedTask ?? state.tasks.first {
                onTaskTap(task.id)
            }
        }
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

    // MARK: - Away Indicator

    private var awayIndicator: some View {
        VStack(spacing: 4) {
            Image(systemName: "person.slash.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(OfficePalette.statusLeave)
            Text("离席中")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(OfficePalette.textMuted)
        }
        .frame(width: spriteSize, height: spriteSize)
        .offset(y: -28)
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

    // MARK: - Document Cards

    private var documentCards: some View {
        HStack(spacing: 4) {
            ForEach(activeTasks.prefix(3)) { task in
                documentCard(for: task)
                    .onTapGesture {
                        onTaskTap(task.id)
                    }
            }
        }
        .offset(y: 26)
    }

    private func documentCard(for task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(statusColor(for: task.status))
                .frame(height: 3)

            Text(task.title)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(OfficePalette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                Circle()
                    .fill(statusColor(for: task.status))
                    .frame(width: 4, height: 4)
                Text(task.status.label)
                    .font(.system(size: 7))
                    .foregroundColor(OfficePalette.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(5)
        .frame(width: 54, height: 38)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(OfficePalette.deskShadow.opacity(0.5), lineWidth: 1)
        )
        .rotationEffect(.degrees(Double.random(in: -4...4, seed: task.id)))
    }

    private var activeTasks: [TaskItem] {
        state.tasks.filter { $0.status != .archived }
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

    private func statusColor(for status: TaskStatus) -> Color {
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

    // MARK: - Hover Status Card

    private var hoverCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(state.profile.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OfficePalette.textPrimary)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Text(state.statusLabel)
                    .font(.system(size: 11))
                    .foregroundColor(OfficePalette.textPrimary)
                Spacer()
                Text("Gateway: \(state.profile.gatewayStatus.label)")
                    .font(.system(size: 10))
                    .foregroundColor(OfficePalette.textMuted)
            }

            if let task = state.runningTask ?? state.blockedTask {
                Divider()
                    .background(OfficePalette.deskShadow.opacity(0.4))
                    .padding(.vertical, 2)

                Text(task.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(OfficePalette.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(task.status.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(statusColor(for: task.status))
                    if !task.priority.isEmpty {
                        Text(task.priority)
                            .font(.system(size: 9))
                            .foregroundColor(OfficePalette.textMuted)
                    }
                }
            }

            if !activeTasks.isEmpty {
                HStack(spacing: 6) {
                    countPill(status: .todo, label: "待办")
                    countPill(status: .ready, label: "就绪")
                    countPill(status: .running, label: "进行中")
                    countPill(status: .blocked, label: "阻塞")
                    countPill(status: .done, label: "完成")
                }
            }
        }
        .padding(10)
        .frame(width: 190, alignment: .leading)
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

    private func countPill(status: TaskStatus, label: String) -> some View {
        let count = state.taskCounts[status] ?? 0
        return Group {
            if count > 0 {
                Text("\(label) \(count)")
                    .font(.system(size: 9))
                    .foregroundColor(OfficePalette.textMuted)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Seeded Random

private extension Double {
    static func random(in range: ClosedRange<Double>, seed: String) -> Double {
        var hasher = Hasher()
        hasher.combine(seed)
        let hash = abs(hasher.finalize())
        let t = Double(hash % 1000) / 1000.0
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }
}
