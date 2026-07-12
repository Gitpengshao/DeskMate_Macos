# 任务看板 2D 办公室改造方案

## 背景与目标
当前 `TaskBoardPage` 渲染的是 Kanban 列视图。需要把它整体改造为一个类似 2D 游戏的可视化办公室：
- 办公室背景色严格为 `#fbf2db`。
- 使用 `SceneAssets.xcassets` 中的图片作为办公室装饰。
- 每个 Hermes profile（agent）对应一张办公桌，并根据其当前任务状态播放对应的精灵动画：
  - 正在工作（有 running 任务）→ `workAtDesk`
  - 空闲 / 摸鱼（有非 running 的活跃任务，或在线但无任务）→ `idle`
  - 离开工位 / 离线（Gateway stopped）→ `leave`
  - 办公室内移动 → `walk`（在状态变化、切换看板或刷新时作为短过渡动画）
- 保留原有业务功能：刷新、Nudge、切换/新建看板、新建任务、任务详情弹窗。

## 关键文件
- 修改：
  - `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/TaskBoardPage.swift`
- 新增：
  - `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/TaskBoardOfficeView.swift`
  - `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/AgentDeskView.swift`
  - `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Models/AgentOfficeState.swift`
  - `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/OfficeLayout.swift`
- 复用：
  - `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/AIChat/SpriteFrameAnimationView.swift`
  - `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Models/SpriteSheetData.swift`
  - `/Users/mac002/Desktop/all/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/TaskBoard/TaskBoardDialogs.swift`

## 实现方案

### 1. 数据模型：`AgentOfficeState`
在 `Models/AgentOfficeState.swift` 中定义一个轻量结构，把 `AgentProfile` 与当前看板中分配给该 agent 的任务合并：
- `profile`：agent 信息（来自 `AgentViewModel.shared.model.profiles`）。
- `tasks`：按 `assignee` 匹配到的任务列表（case-insensitive 匹配 profile.id / name / alias）。
- `targetAnimation`：根据任务和 Gateway 状态推导的目标动画：
  - `profile.gatewayStatus == .stopped` → `.leave`
  - 存在 `status == .running` 的任务 → `.workAtDesk`
  - 其它情况 → `.idle`
- `transition`：管理 `walk` 过渡；当 `targetAnimation` 变化时，先进入 `walk` 约 0.8 秒，再切到目标动画。
- 衍生属性：running 任务、各状态任务计数。

### 2. 布局常量：`OfficeLayout`
在 `Views/TaskBoard/OfficeLayout.swift` 集中管理：
- `bgColor = Color(red: 0.984, green: 0.949, blue: 0.859)`。
- 装饰位置与尺寸：使用 `GeometryReader` 的尺寸进行相对定位，避免窗口缩放时重叠。
- 办公桌排布：根据 profile 数量返回桌面中心点（例如 ≤4 时 2×2，5–6 时 3×2）。

### 3. 单张办公桌：`AgentDeskView`
在 `Views/TaskBoard/AgentDeskView.swift` 中绘制：
- 桌子本体：使用 `RoundedRectangle` + 暖木色（如 `#e8dcc0`）。
- Agent 精灵：`SpriteFrameAnimationView(config: state.currentAnimation.config, ...)`，显示尺寸约 90×90，放在桌面后方。
- 姓名标签：桌下居中。
- 状态徽标：桌角小圆点，颜色对应动画状态。
- 任务计数徽标：桌面下方横向展示 `todo / ready / running / blocked / done` 数量。
- 当前 running 任务：若存在，显示为可点击 pill，点击后打开 `TBTaskDetailPopup`。

### 4. 办公室场景：`TaskBoardOfficeView`
在 `Views/TaskBoard/TaskBoardOfficeView.swift` 中组装：
```swift
ZStack {
    OfficeLayout.bgColor.ignoresSafeArea()
    OfficeDecorationsView()          // 装饰层
    AgentDesksView(...)              // 办公桌层
    OfficeToolbar(...)               // 顶部悬浮工具栏
}
```
- 监听 `TaskBoardViewModel` 的任务列表和 `AgentViewModel.shared` 的 profile 列表。
- 将两者合并为 `[AgentOfficeState]`，用 `ForEach` 渲染办公桌。
- 工具栏保留：刷新、Nudge、切换看板、新建看板、新建任务，与原键盘快捷键保持一致。

### 5. 主入口改造：`TaskBoardPage`
- 将 `mainContent` 替换为 `TaskBoardOfficeView`。
- 保留 `@State` 的 sheet 状态、`TBToastOverlay`、所有 `.sheet` 与键盘快捷键。
- 新增 `@State private var selectedTaskId: String? = nil`，用于从办公桌点击 running 任务后弹出 `TBTaskDetailPopup`。

### 6. 动画复用
- 直接使用现有 `SpriteFrameAnimationView` 和 `PetAnimation.config`。
- 通过外层 `scaleEffect(x: -1)` 实现左右转身，不修改现有视图。
- `workAtDesk` / `idle` / `leave` 使用约 12 fps，`walk` 使用约 18 fps。

### 7. 配色与文本
- 办公室内使用浅色主题：深棕/深灰文字，保证在 `#fbf2db` 背景上可读。
- 现有弹窗（新建任务/看板等）保持当前深色主题，作为悬浮 sheet 使用。

## 验证步骤
1. 构建项目（`Cmd+B`），确保无编译错误。
2. 打开 Task Board tab：
   - 背景色为 `#fbf2db`。
   - 装饰图片可见且位置合理。
   - 每个 profile 有一张办公桌。
3. 动画状态验证：
   - 有 running 任务 → `workAtDesk`。
   - 无 running 但有其它活跃任务 → `idle`。
   - Gateway stopped → `leave`。
   - 切换看板或刷新时短暂显示 `walk`。
4. 功能回归：
   - `Cmd+R` 刷新、`Cmd+N` 新建任务、`Cmd+B` 切换看板、`Cmd+Shift+N` 新建看板、`Cmd+.` Nudge。
   - 点击 running 任务标题打开任务详情弹窗。
5. 响应式测试：调整窗口大小，办公桌与装饰不重叠、不被截断。
