import Foundation

/// 飞书 / Lark 网关配置 — 字段对齐 `~/.hermes/.env` 中的 `FEISHU_*` 变量。
///
/// 官方文档：https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/messaging/feishu
struct FeishuConfig: Equatable {
    var appId: String = ""
    var appSecret: String = ""
    /// `feishu`（中国）或 `lark`（国际版）。
    var domain: String = "feishu"
    /// `websocket`（推荐）或 `webhook`。
    var connectionMode: String = "websocket"
    var allowedUsers: String = ""
    var homeChannel: String = ""

    // 高级
    var groupPolicy: String = "allowlist"
    var requireMention: Bool = true
    var allowBots: String = "none"
    var reactions: Bool = true
    var botOpenId: String = ""
    var botUserId: String = ""
    var botName: String = ""

    // Webhook 模式专用
    var webhookHost: String = "127.0.0.1"
    var webhookPort: String = "8765"
    var webhookPath: String = "/feishu/webhook"
    var encryptKey: String = ""
    var verificationToken: String = ""

    /// 转换为 `.env` 写入项；value 为 nil 或空字符串表示移除该变量。
    func toEnvVars() -> [(key: String, value: String?)] {
        return [
            ("FEISHU_APP_ID", appId),
            ("FEISHU_APP_SECRET", appSecret),
            ("FEISHU_DOMAIN", domain),
            ("FEISHU_CONNECTION_MODE", connectionMode),
            ("FEISHU_ALLOWED_USERS", allowedUsers),
            ("FEISHU_HOME_CHANNEL", homeChannel),
            ("FEISHU_GROUP_POLICY", groupPolicy),
            ("FEISHU_REQUIRE_MENTION", requireMention ? "true" : "false"),
            ("FEISHU_ALLOW_BOTS", allowBots),
            ("FEISHU_REACTIONS", reactions ? "true" : "false"),
            ("FEISHU_BOT_OPEN_ID", botOpenId),
            ("FEISHU_BOT_USER_ID", botUserId),
            ("FEISHU_BOT_NAME", botName),
            ("FEISHU_WEBHOOK_HOST", webhookHost),
            ("FEISHU_WEBHOOK_PORT", webhookPort),
            ("FEISHU_WEBHOOK_PATH", webhookPath),
            ("FEISHU_ENCRYPT_KEY", encryptKey),
            ("FEISHU_VERIFICATION_TOKEN", verificationToken),
        ]
    }

    /// 从 `.env` 字典构造配置，缺失项使用默认值。
    static func fromEnvVars(_ env: [String: String]) -> FeishuConfig {
        var cfg = FeishuConfig()
        cfg.appId = env["FEISHU_APP_ID"] ?? ""
        cfg.appSecret = env["FEISHU_APP_SECRET"] ?? ""
        if let v = env["FEISHU_DOMAIN"], !v.isEmpty { cfg.domain = v }
        if let v = env["FEISHU_CONNECTION_MODE"], !v.isEmpty { cfg.connectionMode = v }
        cfg.allowedUsers = env["FEISHU_ALLOWED_USERS"] ?? ""
        cfg.homeChannel = env["FEISHU_HOME_CHANNEL"] ?? ""
        if let v = env["FEISHU_GROUP_POLICY"], !v.isEmpty { cfg.groupPolicy = v }
        cfg.requireMention = parseBool(env["FEISHU_REQUIRE_MENTION"], default: true)
        if let v = env["FEISHU_ALLOW_BOTS"], !v.isEmpty { cfg.allowBots = v }
        cfg.reactions = parseBool(env["FEISHU_REACTIONS"], default: true)
        cfg.botOpenId = env["FEISHU_BOT_OPEN_ID"] ?? ""
        cfg.botUserId = env["FEISHU_BOT_USER_ID"] ?? ""
        cfg.botName = env["FEISHU_BOT_NAME"] ?? ""
        if let v = env["FEISHU_WEBHOOK_HOST"], !v.isEmpty { cfg.webhookHost = v }
        if let v = env["FEISHU_WEBHOOK_PORT"], !v.isEmpty { cfg.webhookPort = v }
        if let v = env["FEISHU_WEBHOOK_PATH"], !v.isEmpty { cfg.webhookPath = v }
        cfg.encryptKey = env["FEISHU_ENCRYPT_KEY"] ?? ""
        cfg.verificationToken = env["FEISHU_VERIFICATION_TOKEN"] ?? ""
        return cfg
    }
}

/// 微信（Weixin / WeChat）网关配置 — 字段对齐 `~/.hermes/.env` 中的 `WEIXIN_*` 变量。
///
/// 官方文档：https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/messaging/weixin
struct WeixinConfig: Equatable {
    var accountId: String = ""
    var token: String = ""
    var dmPolicy: String = "open"
    var allowedUsers: String = ""
    var homeChannel: String = ""

    // 高级
    var groupPolicy: String = "disabled"
    var groupAllowedUsers: String = ""
    var baseUrl: String = "https://ilinkai.weixin.qq.com"
    var cdnBaseUrl: String = "https://novac2c.cdn.weixin.qq.com/c2c"
    var homeChannelName: String = "Home"
    var allowAllUsers: String = ""
    var splitMultilineMessages: Bool = false

    func toEnvVars() -> [(key: String, value: String?)] {
        return [
            ("WEIXIN_ACCOUNT_ID", accountId),
            ("WEIXIN_TOKEN", token),
            ("WEIXIN_DM_POLICY", dmPolicy),
            ("WEIXIN_ALLOWED_USERS", allowedUsers),
            ("WEIXIN_HOME_CHANNEL", homeChannel),
            ("WEIXIN_GROUP_POLICY", groupPolicy),
            ("WEIXIN_GROUP_ALLOWED_USERS", groupAllowedUsers),
            ("WEIXIN_BASE_URL", baseUrl),
            ("WEIXIN_CDN_BASE_URL", cdnBaseUrl),
            ("WEIXIN_HOME_CHANNEL_NAME", homeChannelName),
            ("WEIXIN_ALLOW_ALL_USERS", allowAllUsers),
            ("WEIXIN_SPLIT_MULTILINE_MESSAGES", splitMultilineMessages ? "true" : "false"),
        ]
    }

    static func fromEnvVars(_ env: [String: String]) -> WeixinConfig {
        var cfg = WeixinConfig()
        cfg.accountId = env["WEIXIN_ACCOUNT_ID"] ?? ""
        cfg.token = env["WEIXIN_TOKEN"] ?? ""
        if let v = env["WEIXIN_DM_POLICY"], !v.isEmpty { cfg.dmPolicy = v }
        cfg.allowedUsers = env["WEIXIN_ALLOWED_USERS"] ?? ""
        cfg.homeChannel = env["WEIXIN_HOME_CHANNEL"] ?? ""
        if let v = env["WEIXIN_GROUP_POLICY"], !v.isEmpty { cfg.groupPolicy = v }
        cfg.groupAllowedUsers = env["WEIXIN_GROUP_ALLOWED_USERS"] ?? ""
        if let v = env["WEIXIN_BASE_URL"], !v.isEmpty { cfg.baseUrl = v }
        if let v = env["WEIXIN_CDN_BASE_URL"], !v.isEmpty { cfg.cdnBaseUrl = v }
        if let v = env["WEIXIN_HOME_CHANNEL_NAME"], !v.isEmpty { cfg.homeChannelName = v }
        cfg.allowAllUsers = env["WEIXIN_ALLOW_ALL_USERS"] ?? ""
        cfg.splitMultilineMessages = parseBool(env["WEIXIN_SPLIT_MULTILINE_MESSAGES"], default: false)
        return cfg
    }
}

/// 解析 `.env` 中的布尔值；未设置或无法识别时使用 `default`。
private func parseBool(_ raw: String?, default: Bool) -> Bool {
    guard let v = raw?.trimmingCharacters(in: .whitespaces).lowercased() else { return `default` }
    if v.isEmpty { return `default` }
    return v == "true" || v == "1" || v == "yes"
}
