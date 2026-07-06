# 智能体页面重构计划

## 1. Summary（目标）

将 `AgentPage` 从复杂的 Hermes profile 管理器简化为 **左侧智能体列表 + 右侧会话** 的页面：

- 左侧展示可搜索的智能体（profile）列表，支持新建/编辑/删除。
- 右侧复用现有 `AIChat` 组件（`AiChatPage`、`MessageBubbles`、`InputBar`、`SessionSidebar`）作为该智能体的独立会话界面。
- 选中智能体时，真正切换到对应的 Hermes profile 并启动其 Gateway 进程，实现配置/会话完全隔离。
- 避免频繁启停 Gateway：已启动的 Gateway 保持运行，切换时只换客户端与 ViewModel；App 退出时统一停止全部 Gateway。
- 移除旧页面中的 Gateway 启停按钮、Distribution 安装/更新、导出、`useProfile` 等高级功能。

## 2. Current State Analysis（现状）

| 文件 | 现状 |
|------|------|
| `DeskMate/Services/HermesGatewayService.swift` | **✅ 已完成多进程注册表改造**：使用 `Registry` actor 维护 `[String: GatewayInstance]`，default 固定端口 `8642`，其它 profile 动态扫描 `8643~8700`；已提供 `ensureGatewayRunning(for:)`, `stopGateway(for:)`, `stopAllGateways()`, `client(for:)`。 |
| `DeskMate/ViewModels/AiChatViewModel.swift` | **✅ 已支持 profile 注入**：`init` 新增 `profile: String? = nil`，`configWriter` 与 `modelConfigService` 均按 profile 隔离，`AiChatPage` 的 `InputBar` 已改用 `chatVM.profile`。 |
| `DeskMate/ViewModels/SessionListViewModel.swift` | **✅ 已支持 profile 注入**：`init(gateway:profile:)` 新增 `profile: String?`。 |
| `DeskMate/Services/SessionApiService.swift` | **✅ 已支持 profile 隔离**：`init(client:profile:)` 将缓存写到 `~/.hermes/profiles/<id>/chat_cache.json`。 |
| `DeskMate/ViewModels/AgentChatContainer.swift` | **✅ 已创建**：用于按 profile 缓存 `AiChatViewModel` 与 `SessionListViewModel`。 |
| `DeskMate/ViewModels/AgentViewModel.swift` | **部分完成**：已新增 `@Published chatContainers`、`selectProfile(_:)`、`prepareChat(for:)` 等按 profile 缓存与切换逻辑；但仍保留 `startGateway`/`stopGateway`/`installGatewayService`/`exportProfile`/`installDistribution` 等旧高级方法，需要清理。 |
| `DeskMate/Views/AgentManagement/AgentPage.swift` | **未完成**：右侧仍是 `profileDetailScroll` 详情面板（基本信息/运行时/Distribution/Gateway/危险操作），尚未改为 `AiChatPage`；仍保留 `InstallDistributionDialog` 的 sheet 与快捷键。 |
| `DeskMate/Views/AgentManagement/AgentComponents.swift` | **部分完成**：`AgentProfileRow`、`AgentToolbar`、`AgentSideFilter`、`AgentEmptyView` 已简化；`AgentFieldRow`/`AgentDetailSectionHeader`/`DetailActionButton` 等详情组件保留但后续不再使用。 |
| `DeskMate/Views/AgentManagement/AgentDialogs.swift` | **未完成**：`InstallDistributionDialog` 仍完整存在，需要删除。 |
| `DeskMate/Models/AgentModel.swift` | **未完成**：`AgentProfile` 仍保留大量 Distribution/Gateway 字段；`AgentPageModel` 仍可能包含 `showOnlyDistributions` 等旧状态。 |
| `DeskMate/App/DeskMateApp.swift` | **未完成**：尚未实现 `applicationShouldTerminate` 统一停止所有 Gateway。 |
| `DeskMate/Views/Main/MainContentArea.swift` | 「AI 对话」tab 继续使用全局 `AiChatViewModel()` / `SessionListViewModel()`；「智能体」tab 只展示 `AgentPage()`。 |

## 3. Assumptions & Decisions（决策）

1. **真正的 Hermes profile 隔离**：每个非默认智能体启动独立的 Gateway 子进程，使用独立的 `~/.hermes/profiles/<id>` 目录，会话、配置、缓存完全隔离。
2. **默认 profile 保持兼容**：默认智能体（`default` / `nil`）继续使用固定端口 `8642`，与现有「AI 对话」tab 共用同一 Gateway 进程。
3. **避免频繁启停**：切换左侧智能体时只切换 `GatewayClient` 和 ViewModel 缓存；已启动的 Gateway 不停止。
4. **右侧完全复用 `AiChatPage`**：不新建 `AgentChatView`，只通过注入不同 `profile` 的 `AiChatViewModel`/`SessionListViewModel` 实现隔离。
5. **移除高级功能**：Gateway 手动启停、Distribution 安装/更新、导出、`useProfile`、系统服务安装等全部从 UI 和 ViewModel 移除。
6. **App 退出清理**：在 `applicationShouldTerminate` 中异步停止所有 Gateway，避免僵尸进程。
7. **端口策略**：默认 `8642`；其它智能体从 `8643` 开始扫描可用端口，上限 `8700`，避免无限增长。

## 4. Proposed Changes（具体改动）

### 4.1 `DeskMate/Services/HermesGatewayService.swift` — 多进程注册表改造（已完成）

- 新增私有结构 `GatewayInstance`：
  ```swift
  private struct GatewayInstance {
      let process: Process
      let port: Int
      let apiKey: String
      let profile: String?   // nil 表示 default
      let isReady: Bool
  }
  ```
- 用 `[String: GatewayInstance]` 维护注册表，key 用 `""` 表示 default profile，`profileId` 表示其它智能体。
- 保留旧签名 `startGateway(profile:port:)` 与 `stopGateway(port:)`，内部转发到新逻辑，保证「AI 对话」tab 和旧调用点不崩溃。
- 新增核心方法：
  - `ensureGatewayRunning(for profile: String?) async -> (port: Int, apiKey: String)?`
  - `stopGateway(for profile: String?) async`
  - `stopAllGateways() async`
  - `isRunning(profile: String?) -> Bool`
  - `client(for profile: String?) -> GatewayClient`（构造对应 port/apiKey 的 `GatewayClient`）
- 动态端口分配：非 default 从 `8643` 扫描到 `8700`，调用 `isPortInUse` 找第一个空闲端口。
- 启动参数显式传入 `--port <port>`：
  ```swift
  var args = ["-m", "hermes_cli.main"]
  if let profile = profile { args += ["--profile", profile] }
  args += ["gateway", "run"]
  ```
- 每个 profile 使用自己目录下的 `.env` 生成/读取 `API_SERVER_KEY`（`ensureApiServerKey` 需要接受 `hermesHome` 参数）。

### 4.2 `DeskMate/ViewModels/AiChatViewModel.swift` — 注入 profile

实际路径：`DeskMate/ViewModels/AiChatViewModel.swift`（注意不在 `Views/AIChat/` 下）。

- `init` 增加 `profile: String? = nil` 参数。
- 将 `configWriter` 从计算属性改为由初始化时注入：
  ```swift
  let writer = configWriter ?? HermesConfigWriter.forProfile(profile)
  ```
- `modelConfigService` 使用 `ModelConfigService(hermesHome: AppConstants.resolveHermesHome(for: profile))`。
- 暴露 `let profile: String?` 属性，供 `AiChatPage` 的 `InputBar` 使用。
- 保持默认参数行为不变：不传 `gateway` 时仍回退到 `GatewayClient.shared`，确保「AI 对话」tab 继续可用。

### 4.3 `DeskMate/ViewModels/SessionListViewModel.swift` / `DeskMate/Services/SessionApiService.swift` — profile 隔离

- `SessionListViewModel.init(gateway:profile:)` 增加 `profile: String?`。
- `SessionApiService.init(client:hermesHome:)` 增加 `hermesHome: String?`，默认使用 `AppConstants.resolveHermesHome(for: profile)`。
- 缓存文件写到各自 profile 目录：`~/.hermes/profiles/<id>/chat_cache.json`；default 仍是 `~/.hermes/chat_cache.json`。

### 4.4 `DeskMate/Views/AIChat/AiChatPage.swift` — 使用 chatVM.profile

- 将 `InputBar` 的 `currentProfile` 参数从 `HermesGatewayService.shared.currentProfile` 改为 `chatVM.profile`。
- 其余逻辑保持不变。

### 4.5 新建 `DeskMate/ViewModels/AgentChatContainer.swift`

```swift
@MainActor
final class AgentChatContainer: ObservableObject {
    let profileId: String
    let chatVM: AiChatViewModel
    let sessionVM: SessionListViewModel

    init(profileId: String, chatVM: AiChatViewModel, sessionVM: SessionListViewModel) {
        self.profileId = profileId
        self.chatVM = chatVM
        self.sessionVM = sessionVM
    }
}
```

仅作为 `AgentViewModel` 按 profile 缓存聊天/会话 VM 的容器。

### 4.6 `DeskMate/ViewModels/AgentViewModel.swift` — 重写核心逻辑

- 删除：Gateway 启停、Distribution 安装/更新、导出、`useProfile` 等旧方法。
- 删除：页面状态中的 `showOnlyDistributions` 相关逻辑（`toggleDistributionFilter` 等）。
- 保留：`createProfile`/`renameProfile`/`describeProfile`/`deleteProfile`/`refresh`/`silentRefresh`/`loadProfiles`。
- 新增：
  ```swift
  @Published private(set) var chatContainers: [String: AgentChatContainer] = [:]
  func selectProfile(_ id: String) async
  func prepareChat(for profileId: String) async
  func chatContainer(for profileId: String) -> AgentChatContainer?
  ```
- `selectProfile` 流程：
  1. 设置 `model.selectedProfileId`。
  2. 调用 `HermesGatewayService.shared.ensureGatewayRunning(for: id)`。
  3. 用返回的 `(port, apiKey)` 构造 `GatewayClient(host: "127.0.0.1", port: port, apiKey: apiKey)`。
  4. 若 `chatContainers[id]` 不存在，创建：
     ```swift
     let chatVM = AiChatViewModel(gateway: client, profile: id)
     let sessionVM = SessionListViewModel(gateway: client, profile: id)
     chatContainers[id] = AgentChatContainer(profileId: id, chatVM: chatVM, sessionVM: sessionVM)
     ```
  5. 触发 `sessionVM.loadSessions()`、`chatVM.loadCurrentModel()`、`chatVM.loadWorkingDirectory()`。
- `deleteProfile` 流程：先 `stopGateway(for: id)` 并移除容器，再调用 `AgentService.deleteProfile`。
- `renameProfile` 流程：先停止旧 Gateway 并移除容器，执行 rename 后重新选中（会重新启动新名称的 Gateway）。
- `createProfile` 成功后自动选中新 profile，触发 prepareChat。

### 4.7 `DeskMate/Views/AgentManagement/AgentPage.swift` — 右侧改为会话

- 左侧保持列表（搜索 + 列表 + 新建按钮），但简化 `AgentProfileRow`（移除 Gateway 状态点、distribution 图标）。
- 右侧改为：
  - 未选中：空状态。
  - 已选中但 Gateway 未就绪：显示「正在启动 Gateway…」+ 重试按钮。
  - 已就绪：`AiChatPage(chatVM: container.chatVM, sessionVM: container.sessionVM, isDark: true)`。
- 工具栏只保留：刷新、新建。
- Sheet 只保留：New / Rename / Describe / Delete。
- 移除 `InstallDistributionDialog` 的 sheet 和 ⌘⇧I 快捷键。
- `selectProfile` 调用需要改为 `Task { await viewModel.selectProfile(p.id) }`。

### 4.8 `DeskMate/Views/AgentManagement/AgentComponents.swift` — 简化

- `AgentProfileRow`：保留头像、名称、描述/模型，移除 Gateway 状态点与 distribution 图标。
- `AgentToolbar`：只保留刷新与新建，移除 distribution 安装按钮和文档按钮。
- `AgentSideFilter`：只保留搜索框和总数 chip，移除 distribution 过滤器和 distribution 计数。
- `AgentEmptyView`：只保留新建按钮，移除 distribution 安装按钮。
- `AgentFieldRow`、`AgentDetailSectionHeader`、`DetailActionButton` 等详情组件可保留但不再被 `AgentPage` 使用，暂不删除以免破坏 Preview/其他引用。

### 4.9 `DeskMate/Views/AgentManagement/AgentDialogs.swift` — 清理

- 删除 `InstallDistributionDialog` 结构体及在 `AgentPage` 中的使用。
- 保留 `NewAgentProfileDialog`、`RenameAgentProfileDialog`、`DescribeAgentProfileDialog`、`DeleteAgentProfileDialog`。
- `NewAgentProfileDialog` 可继续支持 blank / clone / cloneAll / cloneFrom，UI 保持简洁。

### 4.10 `DeskMate/Models/AgentModel.swift` — 清理字段

- `AgentProfile` 保留核心字段：`id`、`name`、`description`、`alias`、`path`、`model`、`provider`、`isDefault`、`isActive`。
- `gatewayStatus` 可保留但不再用于 UI；`skillsCount`、`cronCount`、`installedAt`、`isDistribution`/`distributionName`/`distributionVersion`/`distributionSource`/`distributionAuthor`/`distributionLicense` 保留用于列表展示但 `AgentPage` 右侧不再展示。
- `AgentPageModel` 移除 `showOnlyDistributions` 与 `distributionCount` 相关逻辑，只保留搜索、列表、选中、loading、error。
- `AgentCreateMode` 保留。
- `DistributionSourceType` 和 `InstallDistributionDialog` 一起移除（如果只有该对话框使用）。

### 4.11 `DeskMate/App/DeskMateApp.swift` — 退出清理

- 在 `AppDelegate` 中实现：
  ```swift
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
      Task.detached {
          await HermesGatewayService.shared.stopAllGateways()
          await MainActor.run {
              NSApp.reply(toApplicationShouldTerminate: true)
          }
      }
      return .terminateLater
  }
  ```
- 保留默认 Gateway 启动逻辑不变。

### 4.12 `DeskMate/Views/Main/MainContentArea.swift` — 保持不变

- 「AI 对话」tab 继续使用全局 `aiChatViewModel` / `sessionListViewModel`，对应默认 profile（`nil`）。
- 「智能体」tab 继续使用 `AgentPage()`，其内部自行管理按 profile 的 ViewModel 缓存。
- `GatewayConnectionManager` 继续监控默认端口 `8642`，用于主控制台头部徽标；本次重构不扩展其多端口监控能力。

## 5. Implementation Order（实施顺序）

### 已完成
1. ✅ 改造 `HermesGatewayService` 支持多进程注册表与动态端口。
2. ✅ 让 `AiChatViewModel`、`SessionListViewModel`、`SessionApiService` 支持 `profile` 注入。
3. ✅ 调整 `AiChatPage` 的 `InputBar` 使用 `chatVM.profile`。
4. ✅ 新建 `AgentChatContainer.swift`。
5. ✅ 在 `AgentViewModel` 中新增 `chatContainers` 与 `prepareChat(for:)` / `selectProfile(_:)` 异步切换逻辑。

### 已完成
6. ✅ 清理 `AgentViewModel.swift`：已确认旧高级方法此前已移除；补充 `preparingProfileId` 用于右侧启动中状态，删除未使用的 `openProfilesDocs`。
7. ✅ 重写 `AgentPage.swift` 右侧为 `AiChatPage`：移除详情面板与 `InstallDistributionDialog` sheet/快捷键，根据选中状态展示空状态/启动中/聊天界面；列表行悬停显示编辑描述/重命名/删除按钮。
8. ✅ 清理 `AgentDialogs.swift`：删除 `InstallDistributionDialog` 结构体。
9. ✅ 清理 `AgentModel.swift`：移除 `DistributionSourceType`、`showOnlyDistributions`、`distributionCount`、`runningGatewayCount` 等冗余类型与状态；精简 `AgentText` 文案。
10. ✅ 在 `DeskMateApp.swift` 中实现 `applicationShouldTerminate`，退出时异步停止所有 Gateway。
11. ✅ 编译、运行、联调：`xcodebuild` 构建成功，`DeskMate.app` 可正常启动。

## 6. Verification（验证）

1. 启动 App，确认默认 Gateway 仍在 `8642` 启动，「AI 对话」页正常发送消息。
2. 进入「智能体」页，点击非默认 agent：
   - 右侧显示启动进度，随后可聊天。
   - 通过 `lsof -i :8643` 等命令确认该 agent 的 Gateway 已启动。
3. 切换到另一个 agent，确认新端口被占用，旧端口进程仍在运行；再切回原 agent，应瞬间恢复，无重启。
4. 验证每个 agent 的会话缓存写在 `~/.hermes/profiles/<id>/chat_cache.json`。
5. 新建、重命名、编辑描述、删除 agent：
   - 新建后自动选中并可聊天。
   - 重命名后旧 Gateway 停止，新名字重新启动。
   - 删除后对应 Gateway 停止，右侧回到空状态。
6. 启动多个 agent 后 `Cmd+Q` 退出，确认所有 `hermes_cli.main` 进程已停止。

## 7. Risks（风险）

- **端口分配上限**：动态端口扫描应设上限（如 `8700`），避免无限增长。
- **多进程资源**：每个 agent 一个 Gateway 进程会占用更多内存；当前按用户要求保持运行，未来可考虑空闲自动停止。
- **退出超时**：`stopAllGateways()` 应设整体超时，防止某个僵尸进程阻塞 App 退出。
- **默认 profile 双入口**：「AI 对话」页与 Agent 页选择 default 会共享 `8642`，但使用不同的 `AiChatViewModel`，不会互相污染数据。
- **Hermes CLI 端口参数**：需要确认 `python -m hermes_cli.main --profile <id> gateway run --port <port>` 能被 Hermes 正确解析。
