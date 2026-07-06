# 灵动岛今日汇总展示

## Context

当前 DeskMate 进入控制台后，顶部灵动岛没有展示业务内容，仅收起为 compact 状态。用户希望：
- 控制台打开时，鼠标悬浮灵动岛才展开；
- 展开时展示「今日汇总」：今天聊天次数、输入 token、输出 token、总 token；
- 每次聊天结束后也更新汇总数据；
- 不要实时更新浪费性能，数据拉取/聚合走后台线程。

这些数据可从后端会话列表（`/api/sessions`）聚合得到；字段不确定时先打印日志，便于用户确认。

## Goals

1. 控制台打开期间，鼠标悬浮灵动岛 → 展开并展示今日汇总。
2. 控制台关闭或未悬浮时，灵动岛保持原有行为。
3. 每次聊天结束后后台刷新一次汇总数据。
4. 数据拉取与聚合在后台线程执行，避免阻塞主线程/桌宠动画。
5. 先打印原始会话字段日志，方便确认 token 相关字段。

## Recommended Approach

### 1. 新增数据模型 `TodayStats`

文件：`DeskMate/Models/TodayStats.swift`

```swift
struct TodayStats: Equatable {
    let chatCount: Int
    let inputTokens: Int
    let outputTokens: Int
    var totalTokens: Int { inputTokens + outputTokens }
}
```

### 2. 新增聚合服务 `TodayStatsService`

文件：`DeskMate/Services/TodayStatsService.swift`

复用 `SessionApiService`（`DeskMate/Services/SessionApiService.swift`）拉取 `/api/sessions`，避免重复网络逻辑。

职责：
- 拉取全部会话。
- 显式打印每条会话的 `id`、`last_active`、`started_at`、`ended_at`、`input_tokens`、`output_tokens`、`message_count` 等字段（便于用户核对字段名）。
- 按日期过滤：优先使用 `last_active`，其次 `started_at`。支持 Unix 时间戳秒字符串和 ISO8601 两种格式（参考 `SessionSidebar.formatTime` 与 `TaskBoardModel` 的日期解析回退）。
- 聚合今日会话的 `input_tokens` + `output_tokens`，会话数即聊天次数。
- 提供异步方法 `fetchTodayStats() async -> TodayStats`，内部无 MainActor 依赖，纯后台执行。

### 3. 扩展 `DynamicNotchManager`

文件：`DeskMate/Managers/DynamicNotchManager.swift`

新增状态：
```swift
@Published var todayStats: TodayStats?
@Published var isConsoleOpen: Bool = false
@Published var isFetchingTodayStats: Bool = false
```

修改 `DeskMateNotchContent` 视图优先级：
1. `isLoading` → 加载中
2. `isWorking` → 工作中动画
3. `isConsoleOpen && notchSection == .expanded` → 今日汇总视图
4. 默认 → 点击打开控制台

新增方法 `refreshTodayStats()`：
- 使用 `Task.detached(priority: .utility)` 在后台调用 `TodayStatsService.fetchTodayStats()`。
- 通过 `await MainActor.run` 回主线程更新 `todayStats`。
- 用 `isFetchingTodayStats` 防止并发重复请求。

修改 `consoleDidOpen()`：
- 清除 `isLoading`。
- 设置 `isConsoleOpen = true`。
- **不再设置 `disableHoverExpand = true`**，控制台打开期间仍允许鼠标悬浮展开。

修改 `consoleDidClose()`：
- 设置 `isConsoleOpen = false`。
- 清空 `todayStats`。

汇总视图通过读取 SwiftUI Environment 的 `\.notchSection` 判断是否处于 `expanded` 状态；当 expanded 且 `isConsoleOpen` 时调用 `.task { await manager.refreshTodayStats() }` 触发更新。

### 4. 新增汇总视图

在 `DynamicNotchManager.swift` 内的 `DeskMateNotchContent` 中添加私有子视图 `TodaySummaryView`：

- 标题：「今日汇总」
- 数据行：对话次数、输入 token、输出 token、总计 token
- 黑白配色，字号与现有 loading/working 视图一致
- 保持 `minWidth: 260, minHeight: 80` 左右
- 首次获取前显示「今日汇总 加载中…」占位

### 5. 聊天结束后触发刷新

文件：`DeskMate/ViewModels/AiChatViewModel.swift`

在 `onStreamDone()` 中，流结束并调用 `DynamicNotchManager.shared.stopWorking()` 之后，调用：
```swift
DynamicNotchManager.shared.refreshTodayStats()
```

这样每次完整对话结束后后台更新一次汇总，不依赖实时监听。

### 6. `DeskMateApp.swift` 微调

文件：`DeskMate/App/DeskMateApp.swift`

当前 `openMainConsole()` 与 `openConsole()` 在窗口就绪后调用 `notchManager.consoleDidOpen()`，`windowWillClose` 中调用 `notchManager.consoleDidClose()`。逻辑已覆盖，只需确认 `consoleDidOpen`/`consoleDidClose` 内部新增的状态切换即可，AppDelegate 本身无需额外改动。

## Critical Files to Modify

- `DeskMate/Models/TodayStats.swift`（新增）
- `DeskMate/Services/TodayStatsService.swift`（新增）
- `DeskMate/Managers/DynamicNotchManager.swift`（修改）
- `DeskMate/ViewModels/AiChatViewModel.swift`（在 `onStreamDone` 末尾加一行刷新调用）
- `DeskMate/App/DeskMateApp.swift`（确认无需改动）

## Verification

1. 启动应用，完成 Onboarding 并确保 Gateway 运行。
2. 点击灵动岛打开控制台。
3. 鼠标悬浮到灵动岛上，观察是否展开并展示「今日汇总」；同时查看日志中 `TodayStatsService` 打印的原始会话字段。
4. 如果字段名与用户预期不符，用户可复制日志字段给我，我再调整解析逻辑。
5. 鼠标离开，灵动岛自动 compact；关闭控制台后悬浮展开恢复默认「点击打开控制台」。
6. 发送一条 AI 聊天消息，待流结束后观察后台是否打印 `TodayStatsService` 刷新日志。
7. 控制台打开期间发送消息并悬浮灵动岛，确认汇总数据已更新。
