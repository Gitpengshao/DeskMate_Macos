import SwiftUI

/// 飞书 / Lark 配置表单。
///
/// 字段对齐 `~/.hermes/.env` 中的 `FEISHU_*` 变量。
/// 官方文档：https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/messaging/feishu
struct FeishuConfigSection: View {
    @ObservedObject var viewModel: GatewayConfigViewModel

    @State private var showAdvanced: Bool = false

    private var cfg: Binding<FeishuConfig> {
        Binding(
            get: { viewModel.feishuConfig },
            set: { viewModel.feishuConfig = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 顶部操作栏
                actionBar

                // 凭证
                ConfigCard(title: "凭证", subtitle: "在飞书/Lark 开发者控制台创建应用后获取") {
                    VStack(spacing: 0) {
                        ConfigRow(label: "App ID", hint: "FEISHU_APP_ID") {
                            GCTextField(placeholder: "cli_xxx", text: cfg.appId)
                        }
                        ConfigRow(label: "App Secret", hint: "FEISHU_APP_SECRET") {
                            GCSecureField(placeholder: "secret_xxx", text: cfg.appSecret)
                        }
                        ConfigRow(label: "域名", hint: "FEISHU_DOMAIN") {
                            GCPicker(label: "域名", options: [
                                ("feishu", "飞书（中国）"),
                                ("lark", "Lark（国际版）"),
                            ], selection: cfg.domain)
                        }
                    }
                }

                // 连接模式
                ConfigCard(title: "连接模式", subtitle: "FEISHU_CONNECTION_MODE") {
                    VStack(spacing: 8) {
                        GCPicker(label: "连接模式", options: [
                            ("websocket", "WebSocket（推荐，无需公网端点）"),
                            ("webhook", "Webhook（需可访问的 HTTP 端点）"),
                        ], selection: cfg.connectionMode)

                        if cfg.connectionMode.wrappedValue == "webhook" {
                            VStack(spacing: 0) {
                                ConfigRow(label: "Webhook Host", hint: "FEISHU_WEBHOOK_HOST") {
                                    GCTextField(placeholder: "127.0.0.1", text: cfg.webhookHost)
                                }
                                ConfigRow(label: "Webhook Port", hint: "FEISHU_WEBHOOK_PORT") {
                                    GCTextField(placeholder: "8765", text: cfg.webhookPort)
                                }
                                ConfigRow(label: "Webhook Path", hint: "FEISHU_WEBHOOK_PATH") {
                                    GCTextField(placeholder: "/feishu/webhook", text: cfg.webhookPath)
                                }
                                ConfigRow(label: "加密密钥", hint: "FEISHU_ENCRYPT_KEY（推荐）") {
                                    GCSecureField(placeholder: "your-encrypt-key", text: cfg.encryptKey)
                                }
                                ConfigRow(label: "验证 Token", hint: "FEISHU_VERIFICATION_TOKEN") {
                                    GCTextField(placeholder: "your-verification-token", text: cfg.verificationToken)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }

                // 访问控制
                ConfigCard(title: "访问控制", subtitle: "白名单与 Home Channel") {
                    VStack(spacing: 0) {
                        ConfigRow(label: "允许用户", hint: "FEISHU_ALLOWED_USERS（逗号分隔 Open ID）") {
                            GCTextField(placeholder: "ou_xxx,ou_yyy", text: cfg.allowedUsers)
                        }
                        ConfigRow(label: "Home Channel", hint: "FEISHU_HOME_CHANNEL") {
                            GCTextField(placeholder: "oc_xxx", text: cfg.homeChannel)
                        }
                    }
                }

                // 高级设置
                DisclosureGroup(isExpanded: $showAdvanced) {
                    advancedSection
                        .padding(.top, 8)
                } label: {
                    Text("高级设置")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(GCPalette.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(GCPalette.bgPanel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(GCPalette.border, lineWidth: 1)
                        )
                )

                // 保存栏
                saveBar

                // 底部留白
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
        .background(GCPalette.bgBase)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            PrimaryButton(title: "扫码配置", icon: "qrcode") {
                viewModel.startSetup()
            }
            SecondaryButton(title: "打开官方文档", icon: "doc.text") {
                if let url = URL(string: "https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/messaging/feishu") {
                    NSWorkspace.shared.open(url)
                }
            }
            Spacer()
            SecondaryButton(title: "刷新", icon: "arrow.clockwise") {
                viewModel.loadAll()
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(spacing: 0) {
            ConfigRow(label: "群消息策略", hint: "FEISHU_GROUP_POLICY") {
                GCPicker(label: "群消息策略", options: [
                    ("allowlist", "allowlist（默认，仅白名单用户 @提及）"),
                    ("open", "open（任意用户 @提及）"),
                    ("disabled", "disabled（忽略所有群消息）"),
                ], selection: cfg.groupPolicy)
            }
            ConfigRow(label: "需要 @提及", hint: "FEISHU_REQUIRE_MENTION") {
                Toggle("", isOn: cfg.requireMention)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(GCPalette.accent)
            }
            ConfigRow(label: "机器人间消息", hint: "FEISHU_ALLOW_BOTS") {
                GCPicker(label: "机器人间消息", options: [
                    ("none", "none（忽略其他机器人）"),
                    ("mentions", "mentions（仅 @提及 Hermes 时接受）"),
                    ("all", "all（接受所有机器人消息）"),
                ], selection: cfg.allowBots)
            }
            ConfigRow(label: "处理状态回应", hint: "FEISHU_REACTIONS") {
                Toggle("", isOn: cfg.reactions)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(GCPalette.accent)
            }
            ConfigRow(label: "Bot Open ID", hint: "FEISHU_BOT_OPEN_ID（自动检测失败时用）") {
                GCTextField(placeholder: "ou_xxx", text: cfg.botOpenId)
            }
            ConfigRow(label: "Bot User ID", hint: "FEISHU_BOT_USER_ID") {
                GCTextField(placeholder: "xxx", text: cfg.botUserId)
            }
            ConfigRow(label: "Bot 名称", hint: "FEISHU_BOT_NAME") {
                GCTextField(placeholder: "MyBot", text: cfg.botName)
            }
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        HStack(spacing: 12) {
            if let savedAt = viewModel.feishuSavedAt {
                Text("上次保存：\(savedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundColor(GCPalette.textTertiary)
            }
            Spacer()
            PrimaryButton(title: "保存配置", icon: "tray.and.arrow.down") {
                viewModel.saveFeishu()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(GCPalette.bgPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GCPalette.border, lineWidth: 1)
                )
        )
    }
}
