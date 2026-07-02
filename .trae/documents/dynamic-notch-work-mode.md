# 灵动岛展示 AI 工作动画

## Context

当用户发送消息后，AI 聊天页会先在消息气泡中展示 `think` 精灵图帧动画（占位），等 SSE 流第一个 chunk 到达时切换为"流式输出文字"。

当前灵动岛（DynamicNotch）只承担"点击打开控制台"这一种业务。希望叠加一种新的业务态：**当 think 动画结束、AI 开始输出流文字时**，灵动岛自动展开，播放 `work` 精灵图帧动画 + 显示"努力工作中"文字；**当流输出结束（完成 / 停止 / 错误）时**，灵动岛收回到 compact 状态。

资源已就绪：
- `SpriteSheets.work`（[SpriteSheetData.swift#L50-L55](file:///Users/mac002/Desktop/waibao/DeskMate/macosApp/DeskMate/DeskMate/Models/SpriteSheetData.swift#L50-L55)）：6 列 × 30 帧，90×90 native
- `Assets.xcassets/work.imageset/work.png`：540×450 像素
- `SpriteFrameAnimationView`（[SpriteFrameAnimationView.swift](file:///Users/mac002/Desktop/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/AIChat/SpriteFrameAnimationView.swift)）：支持 `displaySize` 参数缩放
- `DynamicNotch` 已有 `expand()` / `compact()` 异步 API

## 改动点

### 1. `DeskMate/Managers/DynamicNotchManager.swift`

**1.1 把 `show()` 改为同步设置 `currentNotch`，异步执行 compact()**
当前 `show()` 把 `currentNotch = notch` 放在 `Task` 内部，存在 race：`startWorking()` 紧接着读 `currentNotch` 仍是 nil。修复：把实例创建挪出 Task，仅保留 `await notch.compact()` 在 Task 中。

**1.2 新增单例**
```swift
@MainActor static let shared = DynamicNotchManager()
```
项目里 `GatewayClient.shared`、`HermesGatewayService.shared` 等都是这个模式。

**1.3 新增工作态**
```swift
@Published var isWorking: Bool = false
```

**1.4 新增 API**
```swift
func startWorking() {            // 幂等：已在工作中则 no-op
    guard !isWorking else { return }
    isWorking = true
    // 1) 若 notch 尚未创建，复用 show() 的同步创建逻辑
    // 2) 调 expand() 展开
    if currentNotch == nil { ensureNotch() }
    Task { [weak self] in await self?.currentNotch?.expand() }
}

func stopWorking() {             // 幂等：未在工作中则 no-op
    guard isWorking else { return }
    isWorking = false
    Task { [weak self] in await self?.currentNotch?.compact() }
}
```

**1.5 抽取 `ensureNotch()` 私有方法**
把 `show()` 里"创建 DynamicNotch + 赋值 currentNotch"的同步部分抽出来，供 `startWorking()` 和 `show()` 复用，避免重复。

**1.6 更新 `DeskMateNotchContent` body 视图分支**
优先级：`isLoading` → `isWorking` → 默认 console 快捷入口。
- `isLoading`：保持现状
- `isWorking`（新增）：HStack { 60×60 work 精灵动画 + 标题"DeskMate" + 副标"努力工作中" }，minHeight ≈ 80，非可点击
- 默认：保持现状

### 2. `DeskMate/App/DeskMateApp.swift`

`private let notchManager = DynamicNotchManager()` → `private let notchManager = DynamicNotchManager.shared`

其他 11 处调用点（`onOpenConsole`、`show()`、`consoleDidOpen()`、`consoleDidClose()` 等）保持不变。

### 3. `DeskMate/ViewModels/AiChatViewModel.swift`

**3.1 新增状态**
```swift
private var hasStartedWorking: Bool = false
```

**3.2 `sendMessage()` 入口处重置**
防御性复位 `hasStartedWorking = false`。

**3.3 `onStreamEvent(.deltaChunk)` 首次触发**
当 `!hasStartedWorking` 时（first chunk）：
- `hasStartedWorking = true`
- 调 `DynamicNotchManager.shared.startWorking()`

**3.4 `onStreamDone()` 结束**
- 重置 `hasStartedWorking = false`
- 调 `DynamicNotchManager.shared.stopWorking()`

**3.5 `stopStream()` 停止**
同上。

**3.6 `handleError()` 错误**
同上。

## 关键文件清单

- [DynamicNotchManager.swift](file:///Users/mac002/Desktop/waibao/DeskMate/macosApp/DeskMate/DeskMate/Managers/DynamicNotchManager.swift) — 主要改动
- [DeskMateApp.swift](file:///Users/mac002/Desktop/waibao/DeskMate/macosApp/DeskMate/DeskMate/App/DeskMateApp.swift) — 切到 shared
- [AiChatViewModel.swift](file:///Users/mac002/Desktop/waibao/DeskMate/macosApp/DeskMate/DeskMate/ViewModels/AiChatViewModel.swift) — 流事件钩子

## 复用已有组件

- `SpriteFrameAnimationView`（[SpriteFrameAnimationView.swift](file:///Users/mac002/Desktop/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/AIChat/SpriteFrameAnimationView.swift)）+ `PetAnimation.work.config` 直接使用
- `DynamicNotch` 的 `expand()` / `compact()` 异步 API（[DynamicNotch.swift](file:///Users/mac002/Desktop/waibao/DeskMate/macosApp/DeskMate/DeskMate/Dependencies/DynamicNotchKit/DynamicNotch/DynamicNotch.swift)）
- 已有 `@MainActor` 隔离 + 单例模式（`GatewayClient.shared` 等）

## 验证

1. 启动 app → 灵动岛 compact 模式显示 DeskMate 标识
2. 打开控制台 → 切到 AI 聊天页
3. 输入消息并发送
4. 期待：消息气泡先显示 think 动画 → 第一个 chunk 到达时
   - 消息气泡切到流式文字
   - **灵动岛从 compact 展开**，显示 work 精灵动画 + "努力工作中"
5. 流结束后
   - **灵动岛收回到 compact**，恢复 DeskMate 标识
6. 错误 / 手动停止流：灵动岛同样收回
7. 工作态时点击灵动岛：当前实现为非可点击（信息展示态），如需点击打开控制台后续可加
8. 控制台打开期间触发流：因 `disableHoverExpand = true`，程序式 `expand()` 仍能展示 work 动画
