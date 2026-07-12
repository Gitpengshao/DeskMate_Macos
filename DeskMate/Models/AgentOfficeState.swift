import Foundation

// MARK: - Animation Phase

/// Agent 在办公室内的动画阶段。
enum AgentAnimationPhase: Equatable {
    /// 已稳定在目标动画。
    case settled
    /// 正在移动中，直到指定时间后切回目标动画。
    case walking(until: Date)
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
        return .idle
    }

    /// 当前应播放的动画（考虑 walk 过渡）。
    var currentAnimation: PetAnimation {
        switch transition {
        case .walking(let until):
            return Date() < until ? .walk : targetAnimation
        case .settled:
            return targetAnimation
        }
    }

    /// 当前正在运行的任务（若有）。
    var runningTask: TaskItem? {
        tasks.first { $0.status == .running }
    }

    /// 各状态任务数量。
    var taskCounts: [TaskStatus: Int] {
        Dictionary(grouping: tasks, by: \.status).mapValues(\.count)
    }

    /// 是否正在 walk 过渡中。
    var isWalking: Bool {
        switch transition {
        case .walking(let until):
            return Date() < until
        case .settled:
            return false
        }
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
