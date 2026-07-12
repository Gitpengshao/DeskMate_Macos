# DeskMate「宠物语音聆听快捷键」实现方案

## 上下文

用户希望在设置页增加一个全局语音快捷键：当桌宠处于可见状态、控制台未打开时，按下快捷键触发 `listen` 动画并开始录音；2 秒没有新语音输入时，自动打开控制台、切换到 AI 对话页并发送刚刚识别的文本。可选同时附加当前桌面截图。该功能涉及权限、全局热键、语音识别、截图、动画、控制台导航与 AI 消息发送。

## 推荐方案

采用「全局热键监听 + 专用语音流程协调器」的架构，尽量复用现有 `SpeechRecognitionManager`、`ImageAttachmentManager`、`PetAnimationManager` 和 `AiChatViewModel`，避免在 AI 聊天内部塞入过多宠物逻辑。

### 关键决策

1. **默认不预设快捷键**：首次使用时为空，用户必须点击录制并设置一个组合键，避免与系统/其他应用冲突。
2. **快捷键为空时开关无法打开**：设置页在快捷键未录制时禁用启用开关。
3. **静默判定基于 partial 转写**：每次收到新的识别文本就重置 2 秒计时器，2 秒内无新文本即视为说完。实现简单且符合需求字面含义。
4. **截图只捕获主显示器**：使用 `CGDisplayCreateImage(CGMainDisplayID())` 生成 `ChatImageAttachment`，后续可扩展为多屏。
5. **全局热键使用 `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`**：需要「辅助功能」权限，实现轻量。若后续发现系统拦截严重，可替换为 Carbon `RegisterEventHotKey`。
6. **语音使用独立 `SpeechRecognitionManager` 实例**：避免与 AI 对话页内的语音按钮互相覆盖回调或污染 `isRecording` 状态。`SpeechRecognitionManager` 的 `private init` 改为内部可访问，全局流程持有私有实例。
7. **`AiChatViewModel` / `MainViewModel` 改为单例共享**：全局流程结束后需要直接操作这两个 ViewModel 来切 tab、填输入框、发送消息。它们原本只在 `MainContentArea` 内部创建，共享后生命周期与 App 一致。

### 新增文件

| 文件 | 用途 |
|------|------|
| `DeskMate/Managers/GlobalShortcutManager.swift` | 注册/注销全局 keyDown 监听器，匹配用户保存的快捷键 |
| `DeskMate/Managers/VoiceShortcutCoordinator.swift` | 协调「动画 → 录音 → 静默检测 → 截图 → 打开控制台 → 发送消息」完整流程 |
| `DeskMate/Views/Components/ShortcutRecorderView.swift` | 快捷键录制 UI：监听局部 keyDown，保存 keyCode + modifierFlags |
| `DeskMate/Models/VoiceShortcut.swift` | 快捷键数据模型 + 显示字符串映射 |
| `DeskMate/Managers/AccessibilityPermissionManager.swift` | 辅助功能权限检查与申请 |

### 修改文件

| 文件 | 修改点 |
|------|--------|
| `DeskMate/Managers/SettingsManager.swift` | 新增 `isVoiceShortcutEnabled`、`voiceShortcut`、`isVoiceShortcutScreenshotEnabled` 及 UserDefaults keys |
| `DeskMate/Views/Main/SettingsPage.swift` | 新增「语音快捷键」区域：启用开关、快捷键录制、截图开关、权限状态提示 |
| `DeskMate/App/DeskMateApp.swift` | `AppDelegate` 暴露 `static weak var shared`、控制台是否打开、桌宠是否可见、打开控制台方法 |
| `DeskMate/Managers/PetWindowController.swift` | 暴露 `isVisible` 属性 |
| `DeskMate/ViewModels/PetViewModel.swift` | 新增 `startListeningAnimation()` / `stopListeningAnimation()` |
| `DeskMate/Managers/SpeechRecognitionManager.swift` | `private init` 改为内部可访问，允许全局流程创建独立实例 |
| `DeskMate/Services/ImageAttachmentManager.swift` | 新增 `captureFullScreenScreenshot(completion:)` 与公开权限检查 API |
| `DeskMate/ViewModels/AiChatViewModel.swift` | 新增 `static let shared = AiChatViewModel()` |
| `DeskMate/ViewModels/MainViewModel.swift` | 新增 `static let shared = MainViewModel()` |
| `DeskMate/Views/Main/MainPage.swift` | 使用 `MainViewModel.shared` |
| `DeskMate/Views/Main/MainContentArea.swift` | 使用 `AiChatViewModel.shared` |
| `DeskMate.xcodeproj/project.pbxproj` | 增加 `INFOPLIST_KEY_NSAccessibilityUsageDescription` |

### 主要流程

```
用户按下全局快捷键
   ↓
GlobalShortcutManager.handle(event)
   ↓
检查：开关启用、桌宠可见、控制台未打开
   ↓
VoiceShortcutCoordinator.startListening()
   ↓
PetViewModel.startListeningAnimation()
SpeechRecognitionManager(独立实例).startRecording()
   ↓
每次 partial 转写 → 重置 2s 静音计时器
   ↓
2s 无新文本 → stopRecording() → 收到 final 文本
   ↓
（可选）ImageAttachmentManager.captureFullScreenScreenshot()
   ↓
AppDelegate.shared?.openConsole()
MainViewModel.shared.switchNav("ai-chat")
AiChatViewModel.shared.updateInput(text)
AiChatViewModel.shared.addImageAttachment(screenshot)
AiChatViewModel.shared.sendMessage()
   ↓
PetViewModel.stopListeningAnimation()
```

### 权限处理

| 权限 | 触发时机 | 检查/申请方式 |
|------|---------|--------------|
| 辅助功能 | 打开「启用全局语音快捷键」开关时 | `AXIsProcessTrustedWithOptions(prompt: true)` |
| 麦克风/语音识别 | 开始录音时（`SpeechRecognitionManager.requestPermissions()`） | 已存在 |
| 屏幕录制 | 打开「同时发送桌面截图」开关时 | `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` |

设置页会展示各项权限状态，未授权时提供「打开系统设置」按钮。如果用户拒绝权限导致功能不可用，开关会被重置为关闭并提示原因。

### UI 设计（SettingsPage 新增区域）

```
语音聆听快捷键
─────────────────────────────────────
[ ] 启用全局语音快捷键
    快捷键： [ 点击录制 ]        ⌘⇧L
    [ ] 同时发送当前桌面截图
    权限状态：辅助功能 ✓  麦克风 ✓  语音识别 ✓  屏幕录制 ⚠
    提示：快捷键仅在桌宠可见且控制台关闭时生效；
          2 秒无语音输入自动结束并发送。
```

## 验证计划

1. **编译**：确保新增文件已加入 target，`project.pbxproj` 的 Info.plist 设置正确，`xcodebuild` 成功。
2. **录制快捷键**：设置页点击录制框，按下 `⌘⇧L`，显示与实际一致。
3. **权限提示**：未授权辅助功能时打开开关，弹出系统授权弹窗；设置页状态同步更新。
4. **正常触发**：桌宠可见、控制台关闭时按快捷键 → 桌宠播放 listen 动画 → 说话 → 2 秒静音 → 控制台打开并切到 AI 对话 → 文本进入输入框并自动发送；开启截图开关时消息附带图片。
5. **忽略场景**：控制台已打开、桌宠隐藏、开关关闭、识别过程中重复按快捷键均不触发。
6. **错误处理**：拒绝麦克风/语音识别权限后，listen 动画停止，不打开控制台；拒绝屏幕录制但开启截图时，仅发送文本并提示一次。

## 风险与假设

- 全局 keyDown 监听必须获得辅助功能权限，否则无任何响应；用户需手动在系统设置中授权。
- 2 秒静默基于识别回调，小声或识别延迟可能导致提前结束。
- 截图仅捕获主显示器。
- `AiChatViewModel.shared` / `MainViewModel.shared` 为单例，当前设计支持；若未来出现多窗口/多会话需重新评估。
