import Foundation

/// 应用层常量 — 对齐 Flutter `AppConstants`。
enum AppConstants {
    static let appName = "DeskMate"
    static let appVersion = "1.0.0"

    // ---- Hermes ----
    nonisolated static let hermesHomeEnvKey = "HERMES_HOME"
    nonisolated static let hermesDefaultDir = ".hermes"
    nonisolated static let hermesAgentDir = "hermes-agent"
    nonisolated static let hermesVenvDir = "venv"

    /// `~/.hermes/config.yaml` — 主模型与辅助任务的核心配置。
    nonisolated static let hermesConfigFile = "config.yaml"
    /// `~/.hermes/.env` — API key 等运行时环境变量。
    nonisolated static let hermesEnvFile = ".env"
    /// `~/.hermes/auth.json` — OAuth/token 认证信息。
    nonisolated static let hermesAuthFile = "auth.json"
    /// `~/.hermes/desktop.json` — DeskMate 桌面配置（与 Flutter 对齐）。
    nonisolated static let hermesDesktopConfigFile = "desktop.json"
    /// `~/.hermes/models.json` — 已保存的模型列表。
    nonisolated static let hermesModelsFile = "models.json"

    /// 默认 Gateway API 端口。
    nonisolated static let defaultGatewayPort: Int = 8642

    /// Gateway 健康检查路径。
    nonisolated static let gatewayHealthEndpoint = "/health"

    /// Gateway API 基础路径。
    nonisolated static let gatewayApiBase = "/v1"

    /// 解析 HERMES_HOME 路径，遵循与 Electron / Flutter 相同的优先级：
    /// 环境变量 > 平台默认值（macOS 上为 `~/.hermes`）。
    nonisolated static func resolveHermesHome() -> String {
        if let env = ProcessInfo.processInfo.environment[hermesHomeEnvKey],
           !env.isEmpty {
            return env
        }
        let home = NSHomeDirectory()
        return (home as NSString).appendingPathComponent(hermesDefaultDir)
    }

    /// 解析指定 profile 的 Hermes home 目录。
    ///
    /// - `profile` 为 `nil` / `default` / 空字符串时返回默认 home（`~/.hermes`）。
    /// - 其他情况返回 `~/.hermes/profiles/<profile>/`。
    ///
    /// 官方文档：https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/profiles
    nonisolated static func resolveHermesHome(for profile: String?) -> String {
        let base = resolveHermesHome()
        guard let profile = profile?.trimmingCharacters(in: .whitespacesAndNewlines),
              !profile.isEmpty, profile != "default" else {
            return base
        }
        return ((base as NSString)
            .appendingPathComponent("profiles") as NSString)
            .appendingPathComponent(profile)
    }

    /// 构造 `~/.hermes/<file>` 形式的完整路径。
    nonisolated static func hermesPath(_ file: String) -> String {
        return (resolveHermesHome() as NSString).appendingPathComponent(file)
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// 模型配置（主模型 / 辅助任务模型）发生变更并重启 Gateway 后发送。
    /// 订阅方（如 AI 对话页）应据此刷新会话列表、当前模型显示及当前会话数据。
    static let modelConfigDidChange = Notification.Name("com.deskmate.modelConfigDidChange")
}
