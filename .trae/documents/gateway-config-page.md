# 网关配置页面（Gateway Config Page）实施计划

## Context

桌面端目前只能通过 `MainSidebar` 切换到 AI 对话、智能体、模型配置等页面，但缺少消息网关（Messaging Gateway）的可视化配置入口。用户若要把 Hermes 接入微信、飞书或 Lark，必须打开终端运行 `hermes gateway setup`、手动编辑 `~/.hermes/.env`、再运行 `hermes gateway` 启动——这套流程对非技术用户不友好。

本计划在 `Main` 目录的导航体系中新增「网关配置」页面，把官方文档（[飞书/Lark](https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/messaging/feishu)、[微信](https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/messaging/weixin)）中描述的终端命令全部映射为可视化操作：表单填写凭据、按钮触发扫码、一键启停网关、一键安装依赖。配置项按「常用 + 高级折叠」组织，仅使用默认 profile（`~/.hermes`）。

## 设计要点

### 1. 命令到 UI 的映射

| 终端命令 | UI 操作 |
|---|---|
| `hermes gateway setup`（交互式） | 「扫码配置」按钮 → 弹出 sheet，App 内嵌流式输出 stdout（含二维码 ASCII），底部输入框可向 stdin 发送选择/凭据 |
| `hermes gateway` | 「启动网关」按钮（复用 `HermesGatewayService.shared.startGateway`） |
| Ctrl-C / 关闭终端 | 「停止网关」按钮（复用 `HermesGatewayService.shared.stopGateway`） |
| `pip install aiohttp cryptography` | 「安装微信依赖」按钮（运行 `pip install`，流式输出） |
| `cd ~/.hermes/hermes-agent && uv pip install -e ".[messaging]"` | 「重装 messaging 扩展」按钮 |
| 手动编辑 `~/.hermes/.env` | 飞书/微信两个 Tab 的表单，保存时写入 `.env` |
| 手动编辑 `~/.hermes/config.yaml` | 高级折叠区中的群组规则等字段 |

### 2. 配置项分组（按文档整理）

**飞书 / Lark Tab**
- 常用：`FEISHU_APP_ID`、`FEISHU_APP_SECRET`、`FEISHU_DOMAIN`（feishu/lark 单选）、`FEISHU_CONNECTION_MODE`（websocket/webhook 单选）、`FEISHU_ALLOWED_USERS`、`FEISHU_HOME_CHANNEL`
- 高级折叠：`FEISHU_GROUP_POLICY`、`FEISHU_REQUIRE_MENTION`、`FEISHU_ALLOW_BOTS`、`FEISHU_REACTIONS`、`FEISHU_BOT_OPEN_ID`/`BOT_USER_ID`/`BOT_NAME`、Webhook 模式下的 `WEBHOOK_HOST`/`PORT`/`PATH`/`ENCRYPT_KEY`/`VERIFICATION_TOKEN`

**微信 Tab**
- 常用：「扫码登录」按钮（运行 setup 获取 token，自动写入 `~/.hermes/weixin/accounts/`）、`WEIXIN_ACCOUNT_ID`、`WEIXIN_TOKEN`（扫码后自动填充，可手动覆盖）、`WEIXIN_DM_POLICY`、`WEIXIN_ALLOWED_USERS`、`WEIXIN_HOME_CHANNEL`
- 高级折叠：`WEIXIN_GROUP_POLICY`、`WEIXIN_GROUP_ALLOWED_USERS`、`WEIXIN_BASE_URL`、`WEIXIN_CDN_BASE_URL`、`WEIXIN_HOME_CHANNEL_NAME`、`WEIXIN_ALLOW_ALL_USERS`、`WEIXIN_SPLIT_MULTILINE_MESSAGES`

### 3. 交互式命令的 App 内嵌流式输出

`StreamingProcessRunner`（`Utils/StreamingProcessRunner.swift`）只支持单向 stdout/stderr 捕获，不支持 stdin。`hermes gateway setup` 是交互式的（要选平台、扫码后可能要确认、手动模式要输入凭据），因此需要新增一个支持 stdin 写入的运行器。

**新增 `InteractiveProcessRunner`**（放 `Utils/InteractiveProcessRunner.swift`）：
- 基于 `Process` + 三条 `Pipe`（stdin/stdout/stderr）
- `start(executable:args:environment:onOutput:onExit:)` 启动并持续推送输出
- `send(_ text: String)` 向 stdin 写入一行（自动补 `\n`）
- `terminate()` 杀进程
- stdout/stderr 合并后通过 `onOutput` 回调（每 0.1s 节流推送增量，避免 ASCII 二维码被截断）
- 保留 `Process` 引用以支持取消

扫码 Sheet UI：
- 顶部说明文字（"请在下方按提示操作，用手机扫描二维码"）
- 中部滚动文本视图，等宽字体显示 stdout（含 ASCII 二维码）
- 底部 HStack：输入框 + 「发送」按钮 + 「取消」按钮
- Sheet 在进程退出或用户点「完成」后关闭

## 实施步骤

### Step 1: 数据模型 — `Models/GatewayConfigModel.swift`（新增）

定义两个配置结构体，字段对齐文档中的 `.env` 变量名：

```swift
struct FeishuConfig: Equatable {
    var appId: String = ""
    var appSecret: String = ""
    var domain: String = "feishu"        // "feishu" | "lark"
    var connectionMode: String = "websocket"  // "websocket" | "webhook"
    var allowedUsers: String = ""        // 逗号分隔
    var homeChannel: String = ""
    // 高级
    var groupPolicy: String = "allowlist"  // open|allowlist|disabled
    var requireMention: Bool = true
    var allowBots: String = "none"        // none|mentions|all
    var reactions: Bool = true
    var botOpenId: String = ""
    var botUserId: String = ""
    var botName: String = ""
    // webhook 模式
    var webhookHost: String = "127.0.0.1"
    var webhookPort: String = "8765"
    var webhookPath: String = "/feishu/webhook"
    var encryptKey: String = ""
    var verificationToken: String = ""
}

struct WeixinConfig: Equatable {
    var accountId: String = ""
    var token: String = ""
    var dmPolicy: String = "open"        // open|allowlist|disabled|pairing
    var allowedUsers: String = ""
    var homeChannel: String = ""
    // 高级
    var groupPolicy: String = "disabled" // open|allowlist|disabled
    var groupAllowedUsers: String = ""
    var baseUrl: String = "https://ilinkai.weixin.qq.com"
    var cdnBaseUrl: String = "https://novac2c.cdn.weixin.qq.com/c2c"
    var homeChannelName: String = "Home"
    var allowAllUsers: String = ""
    var splitMultilineMessages: Bool = false
}
```

并提供两个方法：`toEnvVars() -> [(key, value)]`、`fromEnvVars([String: String]) -> Self`。

### Step 2: 通用 .env 读写 — 扩展 `HermesConfigWriter.swift`

`HermesConfigWriter` 已有 `readAllEnvVars()`（返回 `[String: String]`）和 `writeApiKeyToEnv(provider:apiKey:)`（按 `PROVIDER_API_KEY` 规则写）。需要新增通用 env 写入 API：

```swift
/// 写入/更新多个 env 变量（key 为空值则移除）。
func writeEnvVars(_ vars: [(key: String, value: String?)])
/// 移除指定前缀的所有 env 变量（如所有 FEISHU_* / WEIXIN_*）。
func removeEnvVarsWithPrefix(_ prefix: String)
```

实现复用现有 `readFileOrEmpty` / `ensureDirectoryExists` / 行级 upsert 逻辑（参考 `writeApiKeyToEnv` 第 518-570 行的模式，抽出为通用方法）。注意：写入前先按前缀移除旧的所有 `FEISHU_*` 或 `WEIXIN_*` 变量，避免残留已删除字段。

### Step 3: 交互式进程运行器 — `Utils/InteractiveProcessRunner.swift`（新增）

按上文「设计要点 3」实现。关键点：
- stdout/stderr 用 `readabilityHandler` 增量捕获（非 `readDataToEndOfFile`，因为要实时显示二维码）
- 输出合并后用 `onOutput(String)` 回调，调用方在 `@MainActor` 上更新 UI
- `send(_:)` 通过 `stdinPipe.fileHandleForWriting.write(text.data + "\n")`
- 提供 `static func openInTerminal(args:)` 作为 fallback（用 `osascript` 唤起 Terminal.app 运行命令）

### Step 4: 服务层 — `Services/MessagingConfigService.swift`（新增）

封装网关配置相关的业务逻辑，UI 层只调它：

```swift
@MainActor
final class MessagingConfigService {
    static let shared = MessagingConfigService()

    func loadFeishuConfig() -> FeishuConfig      // 读 .env → FeishuConfig
    func saveFeishuConfig(_ cfg: FeishuConfig)    // 写 .env
    func loadWeixinConfig() -> WeixinConfig
    func saveWeixinConfig(_ cfg: WeixinConfig)

    /// 启动 `hermes gateway setup` 交互式进程，返回 runner 句柄。
    func startGatewaySetup(onOutput: @escaping (String) -> Void) -> InteractiveProcessRunner
    /// 安装微信依赖 aiohttp + cryptography。
    func installWeixinDeps(onOutput: @escaping (String) -> Void) -> InteractiveProcessRunner
    /// 重装 messaging 扩展。
    func reinstallMessagingExt(onOutput: @escaping (String) -> Void) -> InteractiveProcessRunner

    /// 启动/停止/重启网关 — 直接转发到 HermesGatewayService。
    func startGateway() async -> Bool
    func stopGateway() async
}
```

命令路径解析：
- `hermes` 命令：用 `python -m hermes_cli.main gateway setup`（与 `HermesGatewayService.swift` 一致，参考第 110-134 行），python 路径用 `AppConstants.resolveHermesHome()` + `/hermes-agent/.venv/bin/python`（或复用 `HermesGatewayService` 中 `hermesPython(hermesHome)` 私有方法的逻辑，可提取为内部可见）
- `pip install`：直接用同一 python 路径的 `-m pip install aiohttp cryptography`
- `uv pip install -e ".[messaging]"`：在 `~/.hermes/hermes-agent` 目录下运行

### Step 5: ViewModel — `ViewModels/GatewayConfigViewModel.swift`（新增）

```swift
@MainActor
final class GatewayConfigViewModel: ObservableObject {
    @Published var feishuConfig = FeishuConfig()
    @Published var weixinConfig = WeixinConfig()
    @Published var gatewayStatus: GatewayConnectionManager.Status = .checking
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastSavedAt: Date?

    // 扫码/安装进程的状态
    @Published var interactiveOutput: String = ""
    @Published var isInteractiveRunning = false
    private var currentRunner: InteractiveProcessRunner?

    func loadAll()              // 并行加载两个配置
    func saveFeishu()           // 保存并刷新 lastSavedAt
    func saveWeixin()
    func startSetup()           // 启动 hermes gateway setup，输出写入 interactiveOutput
    func sendInput(_ text: String)
    func cancelInteractive()
    func startGateway() async   // 调 MessagingConfigService + 刷新状态
    func stopGateway() async
    func installWeixinDeps()
    func reinstallMessagingExt()
}
```

监听 `GatewayConnectionManager.shared` 的 `status` 更新 `gatewayStatus`（用 `onAppear` 时 `.assign` 或 `Combine` sink）。

### Step 6: UI — `Views/GatewayConfig/`（新增目录，3 个文件）

遵循 `ModelConfigPage` 的黑白主题风格（`MCPalette` 调色板、`.preferredColorScheme(.dark)`、`ZStack { bgBase.ignoresSafeArea() }`）。

**`GatewayConfigPage.swift`** — 主页面
```
ZStack {
  Palette.bgBase
  VStack {
    pageHeader          // 标题「消息网关配置」+ 副标题 + 网关状态 PillBadge + 启动/停止按钮
    gatewayStatusBar    // 卡片：状态/端口/启动/停止/重启
    TabView {
      FeishuConfigSection(viewModel: viewModel)
      WeixinConfigSection(viewModel: viewModel)
    }
    .tabViewStyle(.automatic)
  }
}
.task { await viewModel.loadAll() }
.sheet(isPresented: $viewModel.isInteractiveRunning) { InteractiveConsoleSheet(viewModel: viewModel) }
```

**`FeishuConfigSection.swift`** — 飞书表单（ScrollView + VStack）
- 「扫码配置」按钮（运行 `hermes gateway setup`）+ 「打开官方文档」按钮
- 分区 1「凭证」：App ID、App Secret（SecureField）、域名（单选 feishu/lark）
- 分区 2「连接模式」：websocket / webhook 单选；webhook 选中时展开 host/port/path/encryptKey/verificationToken
- 分区 3「访问控制」：allowedUsers、homeChannel
- DisclosureGroup「高级设置」：groupPolicy（下拉）、requireMention（开关）、allowBots（下拉）、reactions（开关）、botOpenId/botUserId/botName
- 底部：「保存配置」按钮（调用 `viewModel.saveFeishu()`）+ 上次保存时间

**`WeixinConfigSection.swift`** — 微信表单
- 顶部「扫码登录」按钮（运行 `hermes gateway setup`，提示选择 Weixin）
- 「安装微信依赖」按钮 + 「重装 messaging 扩展」按钮（高级折叠中）
- 分区 1「账号」：accountId、token（SecureField，扫码后自动填充，提示用户点「刷新」读取）
- 分区 2「访问控制」：dmPolicy（下拉）、allowedUsers、homeChannel
- DisclosureGroup「高级设置」：groupPolicy、groupAllowedUsers、baseUrl、cdnBaseUrl、homeChannelName、allowAllUsers、splitMultilineMessages（开关）
- 底部：「保存配置」+ 「刷新（从 .env 重新读取）」按钮

**`GatewayConfigComponents.swift`** — 共享组件
- `ConfigCard`（带标题的分组容器）
- `ConfigRow`（label + 控件的对齐行）
- `PrimaryButton` / `SecondaryButton`（黑白风格）
- `InteractiveConsoleSheet`（扫码/安装的输出 + 输入框 sheet）
- `StatusDot`（彩色状态点）

### Step 7: 接入主导航

**修改 `ViewModels/MainViewModel.swift`**：
- `init()` 的 `navItems` 数组中，在 `skill-management` 之后、`settings` 之前插入：
  ```swift
  SidebarNavItem(id: "gateway-config", labelKey: "sidebarGatewayConfig",
                 iconName: "antenna.radiowaves.left.and.right",
                 sectionKey: "sidebarTools")
  ```
- `itemLabel(_:)` 增加 `case "gateway-config": return "网关配置"`

**修改 `Views/Main/MainContentArea.swift`** 第 72-82 行的 `pageContent` switch：
```swift
case "gateway-config":  GatewayConfigPage()
```

## 关键文件清单

| 类型 | 路径 | 说明 |
|---|---|---|
| 新增 | `DeskMate/Models/GatewayConfigModel.swift` | FeishuConfig / WeixinConfig 数据结构 |
| 新增 | `DeskMate/Utils/InteractiveProcessRunner.swift` | 支持 stdin 的流式进程运行器 |
| 新增 | `DeskMate/Services/MessagingConfigService.swift` | 配置读写 + 命令执行服务 |
| 新增 | `DeskMate/ViewModels/GatewayConfigViewModel.swift` | 页面 ViewModel |
| 新增 | `DeskMate/Views/GatewayConfig/GatewayConfigPage.swift` | 主页面 |
| 新增 | `DeskMate/Views/GatewayConfig/FeishuConfigSection.swift` | 飞书表单 |
| 新增 | `DeskMate/Views/GatewayConfig/WeixinConfigSection.swift` | 微信表单 |
| 新增 | `DeskMate/Views/GatewayConfig/GatewayConfigComponents.swift` | 共享组件 |
| 修改 | `DeskMate/Services/HermesConfigWriter.swift` | 新增 `writeEnvVars` / `removeEnvVarsWithPrefix` 通用方法 |
| 修改 | `DeskMate/ViewModels/MainViewModel.swift` | 新增 `gateway-config` 导航项与 label |
| 修改 | `DeskMate/Views/Main/MainContentArea.swift` | `pageContent` switch 新增 case |

## 复用的现有能力

- `HermesConfigWriter.shared`（`Services/HermesConfigWriter.swift`）：`.env` 读写基础（`readAllEnvVars` 第 575 行、`writeApiKeyToEnv` 第 518 行的行级 upsert 模式）
- `HermesGatewayService.shared`（`Services/HermesGatewayService.swift`）：`startGateway`（第 51 行）、`stopGateway`（第 187 行）、`isHealthy`（第 265 行）
- `GatewayConnectionManager.shared`（`Services/GatewayConnectionManager.swift`）：网关状态监听
- `AppConstants`（`Core/Constants/AppConstants.swift`）：`resolveHermesHome()`、`defaultGatewayPort`、`hermesEnvFile`、`hermesConfigFile`
- `StreamingProcessRunner`（`Utils/StreamingProcessRunner.swift`）：单向命令执行（用于 `pip install` 等非交互场景，避免重复造轮子）
- `MCPalette` 调色板（参考 `Views/ModelConfig/ModelConfigPage.swift`）：黑白主题一致性
- `PillBadge`（`Views/Main/MainContentArea.swift` 第 125 行）：状态徽章

## 验证方式

1. **编译**：`xcodebuild -scheme DeskMate -configuration Debug build`（或在 Xcode 中 ⌘B）确认无编译错误。
2. **导航接入**：启动 App，侧边栏「工具」分组下应出现「网关配置」项，点击后右侧显示新页面，header 标题为「网关配置」。
3. **加载现有配置**：若 `~/.hermes/.env` 中已有 `FEISHU_APP_ID` 等变量，页面打开时应自动回填。
4. **保存飞书配置**：填入 App ID `cli_test` + Secret，点「保存」→ 终端 `cat ~/.hermes/.env` 应看到 `FEISHU_APP_ID=cli_test` 等行，且原有非 FEISHU 变量（如 `OPENAI_API_KEY`）未被破坏。
5. **保存微信配置**：同上，验证 `WEIXIN_*` 变量写入，且 `WEIXIN_BASE_URL` 等默认值正确。
6. **扫码 sheet**：点「扫码配置」→ sheet 弹出，应能看到 `hermes gateway setup` 的 stdout 流（含平台选择提示）；在输入框输入对应数字并发送，应能继续交互；点「取消」应终止进程。
7. **网关启停**：点「启动网关」→ header 的 PillBadge 从「未连接」变「已连接」（最长 30s）；点「停止」→ 变回「未连接」。
8. **依赖安装**：点「安装微信依赖」→ sheet 显示 `pip install` 输出，退出码 0。
9. **回归**：切换到「模型配置」「AI 对话」等其他页面，确认导航和原有功能未受影响。
