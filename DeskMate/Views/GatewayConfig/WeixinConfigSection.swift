import SwiftUI

/// 微信（Weixin / WeChat）配置表单。
///
/// 字段对齐 `~/.hermes/.env` 中的 `WEIXIN_*` 变量。
/// 官方文档：https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/messaging/weixin
struct WeixinConfigSection: View {
    @ObservedObject var viewModel: GatewayConfigViewModel

    @State private var showAdvanced: Bool = false

    private var cfg: Binding<WeixinConfig> {
        Binding(
            get: { viewModel.weixinConfig },
            set: { viewModel.weixinConfig = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 顶部操作栏
                actionBar

                // 账号
                ConfigCard(title: "账号", subtitle: "扫码登录后自动保存凭据") {
                    VStack(spacing: 0) {
                        ConfigRow(label: "Account ID", hint: "WEIXIN_ACCOUNT_ID（必填）") {
                            GCTextField(placeholder: "your-account-id", text: cfg.accountId)
                        }
                        ConfigRow(label: "Token", hint: "WEIXIN_TOKEN（扫码后自动填充）") {
                            GCSecureField(placeholder: "your-bot-token", text: cfg.token)
                        }
                    }
                }

                // 访问控制
                ConfigCard(title: "访问控制", subtitle: "私信策略与白名单") {
                    VStack(spacing: 0) {
                        ConfigRow(label: "私信策略", hint: "WEIXIN_DM_POLICY") {
                            GCPicker(label: "私信策略", options: [
                                ("open", "open（任何人可私信）"),
                                ("allowlist", "allowlist（仅白名单）"),
                                ("disabled", "disabled（忽略私信）"),
                                ("pairing", "pairing（配对模式）"),
                            ], selection: cfg.dmPolicy)
                        }
                        ConfigRow(label: "允许用户", hint: "WEIXIN_ALLOWED_USERS（逗号分隔）") {
                            GCTextField(placeholder: "user_id_1,user_id_2", text: cfg.allowedUsers)
                        }
                        ConfigRow(label: "Home Channel", hint: "WEIXIN_HOME_CHANNEL") {
                            GCTextField(placeholder: "chat_id", text: cfg.homeChannel)
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
            PrimaryButton(title: "扫码登录", icon: "qrcode") {
                viewModel.startSetup()
            }
            SecondaryButton(title: "打开官方文档", icon: "doc.text") {
                if let url = URL(string: "https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/messaging/weixin") {
                    NSWorkspace.shared.open(url)
                }
            }
            Spacer()
            SecondaryButton(title: "从 .env 刷新", icon: "arrow.clockwise") {
                viewModel.reloadWeixinConfig()
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(spacing: 0) {
            ConfigRow(label: "群组策略", hint: "WEIXIN_GROUP_POLICY（iLink bot 通常不推送群事件）") {
                GCPicker(label: "群组策略", options: [
                    ("disabled", "disabled（默认，忽略群消息）"),
                    ("open", "open（响应所有群组）"),
                    ("allowlist", "allowlist（仅白名单群组）"),
                ], selection: cfg.groupPolicy)
            }
            ConfigRow(label: "群组白名单", hint: "WEIXIN_GROUP_ALLOWED_USERS（逗号分隔群聊 ID）") {
                GCTextField(placeholder: "group_id_1,group_id_2", text: cfg.groupAllowedUsers)
            }
            ConfigRow(label: "API Base URL", hint: "WEIXIN_BASE_URL") {
                GCTextField(placeholder: "https://ilinkai.weixin.qq.com", text: cfg.baseUrl)
            }
            ConfigRow(label: "CDN Base URL", hint: "WEIXIN_CDN_BASE_URL") {
                GCTextField(placeholder: "https://novac2c.cdn.weixin.qq.com/c2c", text: cfg.cdnBaseUrl)
            }
            ConfigRow(label: "Home 频道名", hint: "WEIXIN_HOME_CHANNEL_NAME") {
                GCTextField(placeholder: "Home", text: cfg.homeChannelName)
            }
            ConfigRow(label: "Allow All Users", hint: "WEIXIN_ALLOW_ALL_USERS") {
                GCTextField(placeholder: "（留空）", text: cfg.allowAllUsers)
            }
            ConfigRow(label: "拆分多行消息", hint: "WEIXIN_SPLIT_MULTILINE_MESSAGES") {
                Toggle("", isOn: cfg.splitMultilineMessages)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(GCPalette.accent)
            }

            // 依赖管理
            Divider().background(GCPalette.border).padding(.vertical, 8)

            HStack(spacing: 10) {
                SecondaryButton(title: "安装微信依赖", icon: "square.and.arrow.down") {
                    viewModel.installWeixinDeps()
                }
                SecondaryButton(title: "重装 messaging 扩展", icon: "arrow.triangle.2.circlepath") {
                    viewModel.reinstallMessagingExt()
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        HStack(spacing: 12) {
            if let savedAt = viewModel.weixinSavedAt {
                Text("上次保存：\(savedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundColor(GCPalette.textTertiary)
            }
            Spacer()
            PrimaryButton(title: "保存配置", icon: "tray.and.arrow.down") {
                viewModel.saveWeixin()
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
