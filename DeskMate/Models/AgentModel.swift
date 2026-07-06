import Foundation
import SwiftUI

// MARK: - Agent Profile

/// Hermes profile（多智能体）— 对齐官方文档
/// https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/profiles
///
/// 每个 profile 拥有独立的 `config.yaml` / `.env` / `SOUL.md` /
/// 记忆 / 会话 / 技能 / cron / state.db / gateway 进程。
/// 创建后自动成为独立命令别名：`hermes profile create coder` → `coder chat` / `coder setup`。
struct AgentProfile: Identifiable, Equatable, Hashable {
    // MARK: - Identity

    /// 唯一 id（默认 `default` / `coder` / `research-bot` 等）。
    let id: String
    /// 展示名（来自 `--name` 或 `profile.yaml` 的 `name` 字段）。
    var name: String
    /// 描述（来自 `--description` 或 `hermes profile describe`）。
    /// Kanban 编排器会根据此描述把任务路由到合适的 profile。
    var description: String
    /// 命令别名（绝大多数情况下 == id）。
    var alias: String

    // MARK: - Filesystem

    /// 完整路径，例如 `~/.hermes/profiles/coder`。
    /// 默认 profile 固定为 `~/.hermes`。
    var path: String

    // MARK: - Runtime

    /// 使用的模型，例如 `anthropic/claude-sonnet-4`。
    var model: String
    /// provider id，如 `openrouter` / `anthropic` / `custom`。
    var provider: String
    /// gateway 进程状态。
    var gatewayStatus: GatewayStatus
    /// 是否为默认 profile（`~/.hermes` 本身）。
    var isDefault: Bool
    /// 是否为粘性当前 profile（`hermes profile use <name>`）。
    var isActive: Bool
    /// 技能数量。
    var skillsCount: Int
    /// cron 任务数量。
    var cronCount: Int
    /// 已安装时间（ISO 8601 字符串，UI 上可解析为 Date）。
    var installedAt: String

    // MARK: - Distribution

    /// 是否为从 git 仓库安装的 distribution。
    var isDistribution: Bool
    /// distribution 名称，例如 `research-bot`。
    var distributionName: String
    /// distribution 版本（`1.0.0` / `2.3.1`）。
    var distributionVersion: String
    /// distribution 仓库 URL。
    var distributionSource: String
    /// distribution 的作者。
    var distributionAuthor: String
    /// distribution 的 license。
    var distributionLicense: String

    // MARK: - Init

    nonisolated init(
        id: String,
        name: String = "",
        description: String = "",
        alias: String = "",
        path: String = "",
        model: String = "",
        provider: String = "",
        gatewayStatus: GatewayStatus = .unknown,
        isDefault: Bool = false,
        isActive: Bool = false,
        skillsCount: Int = 0,
        cronCount: Int = 0,
        installedAt: String = "",
        isDistribution: Bool = false,
        distributionName: String = "",
        distributionVersion: String = "",
        distributionSource: String = "",
        distributionAuthor: String = "",
        distributionLicense: String = ""
    ) {
        self.id = id
        self.name = name.isEmpty ? id : name
        self.description = description
        self.alias = alias.isEmpty ? id : alias
        self.path = path
        self.model = model
        self.provider = provider
        self.gatewayStatus = gatewayStatus
        self.isDefault = isDefault
        self.isActive = isActive
        self.skillsCount = skillsCount
        self.cronCount = cronCount
        self.installedAt = installedAt
        self.isDistribution = isDistribution
        self.distributionName = distributionName
        self.distributionVersion = distributionVersion
        self.distributionSource = distributionSource
        self.distributionAuthor = distributionAuthor
        self.distributionLicense = distributionLicense
    }

    // MARK: - Derived

    /// 显示标题（优先 `name`）。
    var displayTitle: String { name.isEmpty ? id : name }

    /// 头像字母（取 id 第一个字符）。
    var avatarLetter: String {
        guard let first = id.first else { return "?" }
        return String(first).uppercased()
    }

    /// distribution 标签字符串，例如 `research-bot@1.0.0`。
    var distributionLabel: String {
        if !distributionName.isEmpty && !distributionVersion.isEmpty {
            return "\(distributionName)@\(distributionVersion)"
        }
        if !distributionName.isEmpty { return distributionName }
        return ""
    }

    // MARK: - JSON 解析（对齐 `hermes profile list --json`）

    /// 从 CLI JSON 解析 — 对齐 Flutter `AgentProfile.fromJson`。
    static func fromJson(_ json: [String: Any]) -> AgentProfile {
        let id = (json["id"] as? String) ?? (json["name"] as? String) ?? "default"
        let modelRaw = (json["model"] as? String) ?? ""
        let (prov, mdl) = CurrentModelInfo.parse(modelRaw)
        let dist = json["distribution"] as? [String: Any]
        return AgentProfile(
            id: id,
            name: (json["display_name"] as? String) ?? (json["name"] as? String) ?? id,
            description: (json["description"] as? String) ?? "",
            alias: (json["alias"] as? String) ?? id,
            path: (json["path"] as? String) ?? defaultPathForProfile(id),
            model: mdl,
            provider: (json["provider"] as? String) ?? prov,
            gatewayStatus: GatewayStatus.parse(json["gateway"] as? String),
            isDefault: (json["is_default"] as? Bool) ?? (id == "default"),
            isActive: (json["is_active"] as? Bool) ?? false,
            skillsCount: (json["skills_count"] as? Int) ?? 0,
            cronCount: (json["cron_count"] as? Int) ?? 0,
            installedAt: (json["installed_at"] as? String) ?? "",
            isDistribution: dist != nil,
            distributionName: (dist?["name"] as? String) ?? "",
            distributionVersion: (dist?["version"] as? String) ?? "",
            distributionSource: (dist?["source"] as? String) ?? "",
            distributionAuthor: (dist?["author"] as? String) ?? "",
            distributionLicense: (dist?["license"] as? String) ?? ""
        )
    }

    /// 默认 profile 路径。
    static func defaultPathForProfile(_ id: String) -> String {
        if id == "default" {
            return AppConstants.resolveHermesHome()
        }
        return (AppConstants.resolveHermesHome() as NSString)
            .appendingPathComponent("profiles/\(id)")
    }
}

// MARK: - Gateway Status

/// Gateway 进程状态 — 对齐官方 `hermes profile list` 的 Gateway 列。
enum GatewayStatus: String, Equatable, CaseIterable, Codable {
    case running
    case stopped
    case unknown

    static func parse(_ raw: String?) -> GatewayStatus {
        switch (raw ?? "").lowercased() {
        case "running", "up", "active", "started": return .running
        case "stopped", "down", "inactive", "exited": return .stopped
        default: return .unknown
        }
    }

    var label: String {
        switch self {
        case .running: return "运行中"
        case .stopped: return "已停止"
        case .unknown: return "未知"
        }
    }

    var dotColor: Color {
        switch self {
        case .running: return Color(red: 0.133, green: 0.773, blue: 0.369) // #22C55E
        case .stopped: return Color(red: 0.420, green: 0.420, blue: 0.420) // #6B6B6B
        case .unknown: return Color(red: 0.640, green: 0.640, blue: 0.640) // #A3A3A3
        }
    }
}

// MARK: - Agent Create Mode

/// 新建 profile 模式 — 对齐官方 `hermes profile create` 的所有 flag 组合。
enum AgentCreateMode: String, CaseIterable, Identifiable {
    /// `hermes profile create <name>` — 全新空白 profile。
    case blank
    /// `hermes profile create <name> --clone` — 仅克隆 config + .env + SOUL + skills。
    case clone
    /// `hermes profile create <name> --clone-all` — 复制全部（含记忆等，但排除历史）。
    case cloneAll
    /// `hermes profile create <name> --clone-from <source>` — 从指定 profile 克隆。
    case cloneFrom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank:     return "空白 profile"
        case .clone:     return "克隆配置（--clone）"
        case .cloneAll:  return "克隆全部（--clone-all）"
        case .cloneFrom: return "从指定 profile 克隆"
        }
    }

    var subtitle: String {
        switch self {
        case .blank:
            return "预置内置技能的全新 profile"
        case .clone:
            return "复制 config.yaml / .env / SOUL.md / skills，记忆与会话全新"
        case .cloneAll:
            return "复制全部内容，记忆 / cron / 插件都包含（排除历史数据）"
        case .cloneFrom:
            return "从另一个已存在的 profile 拉取配置 / 技能 / SOUL"
        }
    }

    var systemImage: String {
        switch self {
        case .blank:     return "plus.rectangle.on.rectangle"
        case .clone:     return "doc.on.doc"
        case .cloneAll:  return "shippingbox"
        case .cloneFrom: return "arrow.triangle.branch"
        }
    }
}

// MARK: - Page State Model

/// 多智能体页面单一状态源 — 对齐 Flutter `AgentPageModel`。
struct AgentPageModel: Equatable {

    // MARK: - 列表

    /// 所有 profile（包含默认 `default`）。
    var profiles: [AgentProfile]

    // MARK: - 选中

    /// 当前选中的 profile id（用于右侧详情面板）。
    var selectedProfileId: String

    // MARK: - 状态

    var isLoading: Bool
    /// 静默后台刷新标记（与 isLoading 互斥；为 true 时不显示 loading 视图）。
    var isBackgroundRefreshing: Bool
    var errorMessage: String
    var lastOperationLog: String

    // MARK: - 过滤

    var searchQuery: String

    // MARK: - Init

    init(
        profiles: [AgentProfile] = [],
        selectedProfileId: String = "",
        isLoading: Bool = true,
        isBackgroundRefreshing: Bool = false,
        errorMessage: String = "",
        lastOperationLog: String = "",
        searchQuery: String = ""
    ) {
        self.profiles = profiles
        self.selectedProfileId = selectedProfileId
        self.isLoading = isLoading
        self.isBackgroundRefreshing = isBackgroundRefreshing
        self.errorMessage = errorMessage
        self.lastOperationLog = lastOperationLog
        self.searchQuery = searchQuery
    }

    // MARK: - Derived

    /// 是否有可用缓存（用于决定「立即展示」还是「显示 loading」）。
    var hasCache: Bool { !profiles.isEmpty }

    /// 过滤后的 profile 列表（按 searchQuery）。
    var filteredProfiles: [AgentProfile] {
        var result = profiles
        let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.id.lowercased().contains(q)
                || $0.name.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
                || $0.alias.lowercased().contains(q)
                || $0.model.lowercased().contains(q)
            }
        }
        return result
    }

    /// 选中的 profile。
    var selectedProfile: AgentProfile? {
        profiles.first(where: { $0.id == selectedProfileId })
    }

    /// 当前激活的（粘性）profile。
    var activeProfile: AgentProfile? {
        profiles.first(where: { $0.isActive })
    }

    /// 总 profile 数。
    var totalCount: Int { profiles.count }

    // MARK: - Mutation

    /// 不可变更新。
    func updating(
        profiles: [AgentProfile]? = nil,
        selectedProfileId: String? = nil,
        isLoading: Bool? = nil,
        isBackgroundRefreshing: Bool? = nil,
        errorMessage: String? = nil,
        lastOperationLog: String? = nil,
        clearError: Bool = false,
        searchQuery: String? = nil
    ) -> AgentPageModel {
        var m = self
        if let profiles = profiles { m.profiles = profiles }
        if let selectedProfileId = selectedProfileId {
            m.selectedProfileId = selectedProfileId
        }
        if let isLoading = isLoading { m.isLoading = isLoading }
        if let isBackgroundRefreshing = isBackgroundRefreshing {
            m.isBackgroundRefreshing = isBackgroundRefreshing
        }
        if clearError { m.errorMessage = "" }
        else if let errorMessage = errorMessage { m.errorMessage = errorMessage }
        if let lastOperationLog = lastOperationLog {
            m.lastOperationLog = lastOperationLog
        }
        if let searchQuery = searchQuery { m.searchQuery = searchQuery }
        return m
    }
}
