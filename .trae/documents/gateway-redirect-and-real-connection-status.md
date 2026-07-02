# Gateway 环境缺失重定向 + Main 真实连接状态

## Context（背景）

当前应用存在两个问题：

1. **环境缺失时不跳转 Onboarding**：用户曾完成 onboarding（`onboarding_completed=true`），但 `~/.hermes/hermes-agent/venv/bin/python` 实际不存在（环境被删除/损坏）。`AppDelegate.startHermesGatewayIfNeeded()` 中 `HermesGatewayService.startGateway()` 返回 false，仅打印 `"Hermes Gateway 启动失败"`，但既不重置 onboarding 标志也不引导用户去 OnboardingView 重装环境。结果用户停留在死掉的主控制台，所有 API 调用失败（`Could not connect to the server`）。

2. **Main 页面 Gateway 状态是假的**：[MainContentArea.swift#L49](file:///Users/mac002/Desktop/waibao/DeskMate/macosApp/DeskMate/DeskMate/Views/Main/MainContentArea.swift#L49) 硬编码 `gatewayStatusLabel: String { "Gateway 已连接" }`，无论 Gateway 实际是否存活都显示"已连接"。

目标：进入控制台时检测 Python/Hermes 环境，缺失则自动跳转 OnboardingView 重装；Main 页面状态徽标反映真实 `/health` 探测结果。

## 实现方案

### 文件 1（新建）：`DeskMate/Services/GatewayConnectionManager.swift`

轻量 `@MainActor ObservableObject` 单例，封装周期性 `/health` 探测。**不改造** `HermesGatewayService`（它管理 Process + 异步 start/stop，改成 ObservableObject 风险大），而是只读包装它的 `isHealthy()`。

```swift
@MainActor
final class GatewayConnectionManager: ObservableObject {
    static let shared = GatewayConnectionManager()
    enum Status: Equatable { case checking, connected, disconnected }
    @Published private(set) var status: Status = .checking
    private var timer: Timer?
    private init() {}

    func refresh() async {
        status = await HermesGatewayService.shared.isHealthy() ? .connected : .disconnected
    }
    func startMonitoring() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stopMonitoring() { timer?.invalidate(); timer = nil }
}
```

### 文件 2：`DeskMate/App/DeskMateApp.swift`（AppDelegate）

**新增环境检测 helper**（复用已有公开常量 `AppConstants.hermesAgentDir`/`hermesVenvDir`/`resolveHermesHome()`，镜像 [HermesGatewayService.startGateway#L60-69](file:///Users/mac002/Desktop/waibao/DeskMate/macosApp/DeskMate/DeskMate/Services/HermesGatewayService.swift#L60-69) 的判断）：

```swift
private func isHermesEnvironmentReady() -> Bool {
    let p = "\(AppConstants.resolveHermesHome())/\(AppConstants.hermesAgentDir)/\(AppConstants.hermesVenvDir)/bin/python"
    return FileManager.default.fileExists(atPath: p)
}
```

**`openMainConsole()` 开头加同步守卫**（在 `hidePetWindow()` 之前）：环境缺失 → 重置 `onboarding_completed=false`、关 mainWindow、回调 `openConsole()`（此时标志已 false → 走 Onboarding 分支）：

```swift
guard isHermesEnvironmentReady() else {
    NSLog("[AppDelegate] Hermes 环境缺失，重定向到 Onboarding")
    UserDefaults.standard.set(false, forKey: "onboarding_completed")
    mainWindow?.close(); mainWindow = nil
    openConsole()
    return
}
```

**`startHermesGatewayIfNeeded()` 失败分支**：仅重置标志，**不动窗口**（避免与 openMainConsole 双重重定向；preemptive start 在启动时跑，此时主窗口尚未打开）：

```swift
else {
    NSLog("[AppDelegate] Hermes Gateway 启动失败")
    self.gatewayStarted = false
    if !self.isHermesEnvironmentReady() {
        UserDefaults.standard.set(false, forKey: "onboarding_completed")
    }
}
```

**`openMainConsole()` 两条显示分支**（existing window + 即时创建分支），在 `notchManager.consoleDidOpen()` 之后追加启动监控：
```swift
GatewayConnectionManager.shared.startMonitoring()
Task { await GatewayConnectionManager.shared.refresh() }
```

**`windowWillClose` 的 mainWindow 分支**追加：`GatewayConnectionManager.shared.stopMonitoring()`。

### 文件 3：`DeskMate/Views/Main/MainContentArea.swift`

- 新增 `@ObservedObject private var connection = GatewayConnectionManager.shared`
- 替换第 49 行硬编码为按 `connection.status` 切换：
  - `.checking` → "Gateway 检测中" / 灰点 (`Palette.textTertiary`)
  - `.connected` → "Gateway 已连接" / 绿点 (`Color(red: 0.30, green: 0.85, blue: 0.40)`)
  - `.disconnected` → "Gateway 未连接" / 红点 (`Color(red: 0.95, green: 0.30, blue: 0.30)`)
- `headerBar` 中 `Circle().fill(Palette.textPrimary)` 改为 `Circle().fill(gatewayStatusColor)`

### 文件 4：`DeskMate/Views/Main/MainPage.swift`

**无需改动** —— MainContentArea 直接用 `.shared` 单例。

## 关键设计决策

- **不改造 HermesGatewayService**：它持有 Process + 异步方法，ObservableObject 化风险高；用只读 wrapper 最小化。
- **轻量环境检测而非复用 OnboardingViewModel.checkPython**：后者私有、跑 shell、解析 config.yaml，过重；只需文件存在性检测即可（与 startGateway 的早退判断一致）。
- **失败分支只重置标志、不动窗口**：避免 preemptive start（启动时）与 openMainConsole（用户点击时）双重重定向竞争；两者都在 MainActor 上串行。
- **周期探测只更新状态、不重定向**：Gateway 崩溃 ≠ 环境缺失；避免把用户从控制台中途拽走。重定向只在 console 打开 / gateway 启动失败时触发。
- **重入安全**：`openMainConsole → 重置标志 → openConsole()` 递归调用，内层 openConsole 读到 `onboarding_completed=false` 走 Onboarding 分支；`setActivationPolicy(.regular)` 幂等；`consoleDidOpen()` 只在内层触发一次（openMainConsole 提前 return 不触发）。

## 验证方法

1. **环境缺失跳转**：`rm -rf ~/.hermes/hermes-agent/venv`，确保 `onboarding_completed=true`（`defaults read <bundleid> onboarding_completed` 或先正常完成一次 onboarding）。启动应用，点击灵动岛打开控制台 → 应直接进入 OnboardingView（环境检测步骤），而非主控制台。
2. **真实状态徽标**：环境正常时（`~/.hermes/hermes-agent/venv/bin/python` 存在 + gateway 可启动），打开主控制台 → 徽标先显示"检测中"后变"Gateway 已连接"（绿点）。手动 `kill` gateway 进程 → 10s 内徽标变"Gateway 未连接"（红点）。
3. **回归**：环境正常时 onboarding 完成后重新打开控制台，AI 对话页发送消息应正常流式响应（确认未破坏现有 GatewayClient 流程）。

## 涉及文件清单

- 新建：`DeskMate/Services/GatewayConnectionManager.swift`
- 修改：`DeskMate/App/DeskMateApp.swift`（AppDelegate：helper + openMainConsole 守卫 + 失败分支 + 监控生命周期）
- 修改：`DeskMate/Views/Main/MainContentArea.swift`（真实状态徽标 + 颜色）
- 参考（不改）：`DeskMate/Services/HermesGatewayService.swift`、`DeskMate/Core/Constants/AppConstants.swift`
