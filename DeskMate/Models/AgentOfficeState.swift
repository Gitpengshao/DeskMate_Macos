import Foundation

// MARK: - Animation Phase

/// Agent 在办公室内的动画阶段。
indirect enum AgentAnimationPhase: Equatable {
    /// 已稳定在目标动画。
    case settled
    /// 正在起身离开（leave），结束后进入 next。
    case leaving(until: Date, next: AgentAnimationPhase)
    /// 正在走廊移动（walk），结束后进入 next。
    case walking(until: Date, next: AgentAnimationPhase)
    /// 已离开工位（blocked 状态保持），直到目标变化后 next 会被激活。
    case away(next: AgentAnimationPhase)
}

// MARK: - Office State

/// 将 Hermes profile 与当前看板任务合并，生成一个 agent 在办公室内的完整状态。
struct AgentOfficeState: Identifiable {
    let profile: AgentProfile
    let tasks: [TaskItem]
    let transition: AgentAnimationPhase

    var id: String { profile.id }

    /// 根据 Gateway 与任务状态推导的目标动画。
    var targetAnimation: PetAnimation {
        if profile.gatewayStatus == .stopped { return .leave }
        if tasks.contains(where: { $0.status == .running }) { return .workAtDesk }
        if tasks.contains(where: { $0.status == .blocked }) { return .leave }
        return .idle
    }

    /// 当前应播放的动画（考虑 leave/walk/away 过渡）。
    var currentAnimation: PetAnimation {
        switch resolvedPhase {
        case .leaving:
            return .leave
        case .walking:
            return .walk
        case .settled, .away:
            return targetAnimation
        }
    }

    /// Agent 精灵当前是否可见（away 时隐藏，模拟离席）。
    var isAgentPresent: Bool {
        switch resolvedPhase {
        case .away:
            return false
        case .leaving, .walking, .settled:
            return true
        }
    }

    /// 当前正在运行的任务（若有）。
    var runningTask: TaskItem? {
        tasks.first { $0.status == .running }
    }

    /// 当前被阻塞的任务（若有）。
    var blockedTask: TaskItem? {
        tasks.first { $0.status == .blocked }
    }

    /// 各状态任务数量。
    var taskCounts: [TaskStatus: Int] {
        Dictionary(grouping: tasks, by: \.status).mapValues(\.count)
    }

    /// 当前实际生效的阶段（若过渡已过期则递归解析）。
    private var resolvedPhase: AgentAnimationPhase {
        resolve(transition)
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

    /// 是否正在播放过渡动画。
    var isTransitioning: Bool {
        switch resolvedPhase {
        case .settled, .away:
            return false
        case .leaving, .walking:
            return true
        }
    }

    /// 当前状态描述文本。
    var statusLabel: String {
        if isTransitioning {
            switch resolvedPhase {
            case .leaving: return "起身离席"
            case .walking: return "走廊移动"
            default: return "移动中"
            }
        }
        switch targetAnimation {
        case .workAtDesk: return "专注工作"
        case .idle:       return "空闲等待"
        case .leave:      return "暂时离席"
        default:          return "未知"
        }
    }
}

// MARK: - Phase Builders

extension AgentOfficeState {
    /// 根据上一个目标动画与当前目标动画，生成连贯的过渡阶段。
    ///
    /// - 目标变为 blocked(leave): leave → walk → away
    /// - 目标从 blocked 恢复: walk → settled
    /// - 其它状态转换: walk → settled
    static func phase(
        from previous: PetAnimation,
        to current: PetAnimation,
        previousPhase: AgentAnimationPhase
    ) -> AgentAnimationPhase {
        let now = Date()
        let leaveDuration: TimeInterval = 0.6
        let walkDuration: TimeInterval = 0.8

        // 如果当前目标就是 leave (blocked / gateway stopped)，需要完整离席流程
        if current == .leave {
            // 已经在 away 或正在离席，保持
            switch previousPhase {
            case .away:
                return previousPhase
            case .leaving(let until, _):
                if now < until { return previousPhase }
                // leave 结束，进入 walk → away
                return .walking(until: now.addingTimeInterval(walkDuration), next: .away(next: .settled))
            case .walking(let until, _):
                if now < until { return previousPhase }
                // walk 结束，进入 away
                return .away(next: .settled)
            case .settled:
                // 从 settled 开始 leave → walk → away
                return .leaving(
                    until: now.addingTimeInterval(leaveDuration),
                    next: .walking(until: now.addingTimeInterval(leaveDuration + walkDuration), next: .away(next: .settled))
                )
            }
        }

        // 当前目标不是 leave：如果之前是 leave/away，需要先走回工位
        if previous == .leave {
            switch previousPhase {
            case .away, .leaving, .walking:
                // 走回工位
                return .walking(until: now.addingTimeInterval(walkDuration), next: .settled)
            case .settled:
                return .settled
            }
        }

        // 普通状态转换：walk 过渡
        if previous != current {
            return .walking(until: now.addingTimeInterval(walkDuration), next: .settled)
        }

        // 无变化
        return .settled
    }
}

// MARK: - Task assignment matching

extension AgentOfficeState {
    /// 判断某条任务的 assignee 是否属于当前 profile。
    static func matches(profile: AgentProfile, assignee: String) -> Bool {
        let raw = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return false }
        let candidates = [
            profile.id,
            profile.name,
            profile.alias,
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return candidates.contains(raw.lowercased())
    }
}
