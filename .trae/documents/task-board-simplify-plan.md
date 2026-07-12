# TaskBoard 看板简化计划

## Context

当前 `TaskBoard` 页面是一个全功能 Kanban 配置面板：新建任务包含 10+ 字段、工具栏平铺 5 个按钮、详情弹窗包含 Run History / 评论 / Summary / Metadata / 父子任务 / Triage 分解等高级能力。官方 Hermes Kanban 的核心定位是“持久化任务看板，让多个 Agent 协作完成工作”——人类用户最常用的路径其实是：**选一个 Agent → 告诉它做什么 → 在 2D 办公室动画里看进度 → 必要时点进去收尾**。本次简化目标就是把页面降级到这个核心路径，删除不常用的配置项和后台管理功能；同时清理代码里所有“对齐 Flutter / 还原 Flutter”的注释与文案，保证所有保留按钮都调用真实 `hermes kanban` CLI，不做假功能。

## Goals

1. 新建任务只保留核心字段：标题、描述、Agent 下拉选择。
2. Agent 选择使用真实 profile 下拉框（数据源 `AgentViewModel.shared.model.profiles`）。
3. 主视图坚持 2D 办公室/游戏视角：办公桌、Agent 精灵动画、任务徽章、running 任务 pill。
4. 详情弹窗只保留查看 + 完成 / 阻塞 / 删除三个真实操作。
5. 删除 Kanban 列视图、筛选栏、Triage 快捷操作、评论、Run History、Summary/Metadata 编辑等未使用/低频功能。
6. 工具栏只保留最高频操作，低频管理入口收入溢出菜单。
7. 清理所有“Flutter 端”“一比一还原 Flutter”“对齐 Flutter”等注释与文案。
8. 所有触发真实 Hermes CLI 的异步操作（新建任务、切换看板、新建看板、刷新、Nudge、完成、阻塞、删除等）必须显示 loading 状态。

## Non-Goals

- 不新增后端能力；所有改动复用现有 `TaskBoardService` / `AgentService` CLI 调用。
- 不恢复 Kanban 列视图作为主要视图（用户明确选择 2D 办公室动画）。
- 不自动调用 `decompose` / `specify` / `dispatch` 等后台能力作为默认流程。

## Design

### 1. 新建任务对话框简化（`TaskBoardDialogs.swift`）

- **保留字段**：
  - 标题（必填）
  - 描述（让 Agent 做什么）
  - Agent 下拉（必选，数据来源 `viewModel.agentProfiles`）
- **删除字段**：状态 picker、优先级 picker、branch、tenant、skills、maxRetries、parentIds、assignee 文本框。
- **默认值**：
  - `priority = "P2"`
  - `status = .todo`
  - `tenant = "default"`
  - `workspace = viewModel.defaultWorkspace(for: selectedProfile)`（默认 home 目录，可扩展为 profile 工作目录）
- **实现**：用 `Menu` 实现 Agent 下拉，显示 `AgentProfile.displayTitle`，选中后用 `profile.id` 作为 `assignee` 传给后端。无 Agent 时禁用创建并提示“请先创建智能体”。

### 2. 工具栏简化（`TaskBoardOfficeView.swift`）

- **始终显示**：当前看板名称 pill（点击打开切换看板弹窗）、刷新、新建任务（主按钮）。
- **收入 `…` 溢出菜单**：切换看板、新建看板、Nudge。
- **删除**：独立的“Nudge”“切换看板”“新建看板”平铺按钮。
- **Loading 覆盖**：工具栏按钮触发异步 CLI 时，整个办公室视图显示 `TBLoadingView`（通过 `viewModel.model.isLoading` 控制）。

### 3. Agent desk hover 状态卡（`AgentDeskView.swift`）

- 给 `AgentDeskView` 添加 `@State isHovered` 与 hover 位置跟踪。
- 悬浮时 overlay 一个小卡片，显示：
  - Agent 显示名
  - 当前状态标签：工作中 / 空闲 / 离线 / 移动中
  - Gateway 状态
  - 当前运行任务标题（如有）
  - 任务计数：待办 / 就绪 / 进行中 / 阻塞 / 完成
- 保留现有 task-count badges，但把零散 `.help(...)` 收敛到统一 hover 卡。

### 4. 任务详情弹窗裁剪

- **保留内容**：标题、描述、状态、优先级、负责人、工作目录。
- **保留操作**：完成（Complete，不再要求 summary/metadata）、阻塞/解除阻塞（Block 弹原因输入框）、删除（归档）。
- **删除内容**：Run History、评论区、Summary/Metadata 编辑、父子任务链接、Decompose/Specify 按钮。
- 推荐把裁剪后的弹窗拆到 `TaskBoardTaskDetailPopup.swift`，或保留在 `TaskBoardComponents.swift` 并重写。

### 5. 删除死代码（`TaskBoardComponents.swift`）

删除以下未被 `TaskBoardPage` 引用的组件：
- `TBHeaderRow`
- `TBFilterBar`
- `TBPillInput`
- `TBKanbanColumns`
- `TBKanbanColumn`
- `TBLaneSection`
- `TBTaskCard`
- `TBTriageActionButton`
- `TBTaskRunRow`
- `TBCommentRow`
- `TBDetailRow`（若详情弹窗重写后不再需要）
- `TBSectionTitle`（若详情弹窗移除 run history / comments 后不再需要）
- `FlowLayout`（若 Switch Board Dialog 改用系统布局）

保留并复用：
- `TBPill`
- `TBLoadingView`、`TBEmptyView`、`TBErrorBanner`
- `TBStatusButtonStyle`
- `TBStatusDot`（按需）

### 6. ViewModel 调整（`TaskBoardViewModel.swift`）

- 暴露只读代理：
  ```swift
  var agentProfiles: [AgentProfile] { AgentViewModel.shared.model.profiles }
  ```
- 添加默认 workspace 方法：
  ```swift
  func defaultWorkspace(for profile: AgentProfile?) -> String
  ```
- 可选添加便捷方法：
  ```swift
  func addTask(title: String, body: String, assignee: AgentProfile?) async
  ```
  内部自动填充 priority/status/tenant/workspace。
- 保留核心方法：`addTask`、`completeTask`、`blockTask`、`unblockTask`、`deleteTask`/`archiveTask`、`refresh`、`switchBoard`、`createBoard`、`deleteBoard`、`renameBoard`、`nudgeDispatcher`。
  - 每个异步核心方法内部先设置 `model = model.updating(isLoading: true)`，完成后回到 `@MainActor` 设置 `isLoading: false`。
- 不再从 UI 调用：`decomposeTask`、`specifyTask`、`addComment`、`loadTaskRuns`、`bulkComplete`、`bulkArchive`、`bulkUnblock`、`linkTasks`、`setLanesByProfile`、`setFilter`、`clearFilter`。
  - 这些 Method 可以保留在 ViewModel 中但不再被 UI 引用，或者删除。建议先删除调用关系，Method 本身可后续清理。

### 7. `TaskBoardPage.swift` 调整

- 移除 `availableSkills` 相关 `@State` 和 `.task { loadAvailableSkills() }`。
- 保留的 sheet：新建任务、切换看板、新建看板、任务详情。
- 键盘快捷键保留 ⌘N（新建任务）、⌘R（刷新）；删除 ⌘. Nudge、ESC 清除筛选。⌘B / ⌘⇧N 可保留或移入菜单。

## Critical Files to Modify

- `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/TaskBoardDialogs.swift`
- `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/TaskBoardOfficeView.swift`
- `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/AgentDeskView.swift`
- `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/TaskBoardComponents.swift`
- `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/ViewModels/TaskBoardViewModel.swift`
- `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/TaskBoardPage.swift`

可选新增文件：
- `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/TaskBoardTaskDetailPopup.swift`
- `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/TaskBoardAgentHoverCard.swift`
- `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/TaskBoardOfficeToolbar.swift`

## Verification Checklist

- [ ] 打开 TaskBoard 后只显示 2D 办公室视图和简化工具栏。
- [ ] 点击“新建任务”后对话框只显示：标题、描述、Agent 下拉，其他字段已删除。
- [ ] Agent 下拉列出所有 profile，显示名称正确。
- [ ] 创建任务后对应 Agent desk 上任务计数徽章更新。
- [ ] 任务进入 running 后 Agent 动画从 idle 变为 workAtDesk。
- [ ] 鼠标悬浮在 Agent 上显示状态卡：状态标签、当前 running 任务、Gateway 状态、各状态任务计数。
- [ ] 点击 running 任务 pill 打开详情弹窗，弹窗只显示基本信息 + 完成 / 阻塞 / 删除。
- [ ] Block 任务时弹出原因输入框，提交后任务状态变为 blocked。
- [ ] Complete 任务无需填写 summary/metadata，点击后直接变为 done。
- [ ] Delete 任务后任务从列表消失，后端走 archive。
- [ ] 工具栏溢出菜单可切换看板、新建看板、Nudge。
- [ ] 切换看板后办公室视图重新渲染对应任务。
- [ ] 所有异步操作期间显示 loading（刷新、新建任务、切换/新建看板、Nudge、完成、阻塞、删除）。
- [ ] 代码中不再出现“Flutter”“一比一还原”“对齐 Flutter”等注释/文案。
- [ ] 编译无残留引用警告或错误。
- [ ] 没有调用任何未实现的假 API。
