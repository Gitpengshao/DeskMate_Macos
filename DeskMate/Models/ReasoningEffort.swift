import Foundation

/// 推理强度级别 — 对齐 Hermes 官方文档
/// [`agent.reasoning_effort`](https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/configuration#%E6%8E%A8%E7%90%86%E5%8A%AA%E5%8A%9B%E7%A8%8B%E5%BA%A6) 字段的可选值。
///
/// 官方定义（在 `~/.hermes/config.yaml` 中）：
/// ```yaml
/// agent:
///   reasoning_effort: "medium"  # none | low | minimal | medium | high | xhigh
/// ```
///
/// 语义说明（来自官方文档）：
/// - `none`     — 关闭推理
/// - `minimal`  — 最小推理深度（最快、最便宜）
/// - `low`      — 低推理深度（用于例行、高吞吐任务）
/// - `medium`   — 默认（普通任务推荐）
/// - `high`     — 深度推理（复杂调试/分析/多文件编辑）
/// - `xhigh`    — 最大推理深度（架构决策、安全审查等）
///
/// 运行时调整：执行 `hermes config set agent.reasoning_effort high`。
enum ReasoningEffort: String, CaseIterable, Identifiable, Codable, Equatable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    /// 中文显示名 — 头部徽标与下拉菜单共用。
    var displayName: String {
        switch self {
        case .none:    return "无"
        case .minimal: return "极小"
        case .low:     return "低"
        case .medium:  return "中"
        case .high:    return "高"
        case .xhigh:   return "极高"
        }
    }

    /// 简短描述 — 菜单项副标题。
    var subtitle: String {
        switch self {
        case .none:    return "关闭推理"
        case .minimal: return "极快、极省"
        case .low:     return "例行任务"
        case .medium:  return "默认 · 普通任务"
        case .high:    return "复杂调试 / 分析"
        case .xhigh:   return "架构 / 安全审查"
        }
    }

    /// 从 yaml 字符串解析 — 容错处理。
    static func parse(_ raw: String?) -> ReasoningEffort {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty
        else { return .medium }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return ReasoningEffort(rawValue: trimmed) ?? .medium
    }
}
