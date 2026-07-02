# 修复 Onboarding 第二步安装流程（假进度 / 假完成 / 未装也跳步）

## Context（为什么要改）

用户反馈 onboarding 第二步"安装引擎"存在三个 bug：
1. 进度条是假的——`reportProgress` 把阶段描述文字当成"下载速度"显示，进度按固定阶梯 + `Thread.sleep(0.3)` 走，与命令实际执行无关。
2. 安装完成是假的——`runInstallation` 用了不存在的 git 仓库 `https://github.com/hermes/hermes-agent.git`（正确应为 `NousResearch/hermes-agent`）、所有命令 `2>/dev/null` 吞错误、从不检查退出码，最后无条件 `downloadProgress = 1.0` + `hermesInstalled = true`；且手动 clone+pip 漏装 Node/ripgrep/ffmpeg/uv/PATH。
3. 没安装也跳到第三步——因为进度被强制置 1.0，`canAdvance`（step 1）放行，`handleNext` 直接 `nextStep()`；`isInstallFailed` 永不为真，错误横幅从不出现。

目标：改用官方安装脚本 `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash`，流式读取输出驱动真实进度，以"退出码 0 + `checkHermes()` 验证"双重判定成功；失败时不置进度 1.0、不放行、显示错误横幅。镜像通过进程级 git `insteadOf` 环境变量注入子进程，不污染全局 git config。

用户已确认：①采用官方 install.sh；②保留镜像 UI，用进程级 git insteadOf。

## 复用现有模式（不重新造轮子）

`DeskMate/Services/OpenVikingProvider.swift` 已有经过验证的流式 Process 模式（`runProcess` 第 705 行）：
- 用 `readDataToEndOfFile()` 在后台 `DispatchQueue` 排空管道（避免 `readabilityHandler` 丢数据/死锁）；
- `terminationHandler` + `ResumeOnceFlag` 唤醒 async continuation；
- `OutputTicker` 每 0.4s 节流推送尾部日志；
- 返回 `ProcessResult { exitCode, stdout, stderr }`。

`StreamCapture`/`ResumeOnceFlag`/`OutputTicker` 是该文件末尾的**顶层 `internal final class`**（第 903/923/941 行，非 file-private），模块内可直接复用。

## 实施步骤

### 1. 新建 `DeskMate/Utils/StreamingProcessRunner.swift`
新增一个共享的流式 runner，复用现有 `StreamCapture`/`ResumeOnceFlag`/`OutputTicker`（**不移动、不改 OpenVikingProvider**，零破坏）。

```swift
enum StreamingProcessRunner {
    struct Result { let exitCode: Int32; let stdout: String; let stderr: String }

    static func run(
        executable: String,
        args: [String],
        environment: [String: String]? = nil,   // nil → 继承 ProcessInfo 环境
        timeout: TimeInterval,
        logName: String = "StreamingProcessRunner",
        onOutput: ((String) -> Void)? = nil,        // 每 0.4s 推送尾部非空行
        onProcessReady: ((Process) -> Void)? = nil  // process.run() 后回调，供外部 terminate
    ) async throws -> Result

    static func stripANSI(_ s: String) -> String
    static func lastNonEmptyLines(in: String, max: Int) -> String
}
```
逻辑直接照搬 `OpenVikingProvider.runProcess` 的 readQueue 排空 + terminationHandler resume + OutputTicker 节流 + 超时强杀；新增两处：
- `process.environment = environment ?? ProcessInfo.processInfo.environment`；
- `try process.run()` 成功后立即 `onProcessReady?(process)`。
`stripANSI` / `lastNonEmptyLines` 从 `OpenVikingProvider` 的 `private static` 提升为 internal（复制到本文件，不动原文件）。

> 不重构 OpenVikingProvider 的 `runProcess`——保留其现有实现，避免给已工作功能引入风险。轻微重复优于改动关键路径。

### 2. `DeskMate/Models/OnboardingModel.swift`
- 第 204 行 `canAdvance` step 1 加失败守卫：
  ```swift
  if currentStep == 1 { return downloadProgress >= 1.0 && !isInstalling && !isInstallFailed }
  ```
- Step 2 区块（约第 172 行后）新增字段：
  ```swift
  var installLogTail: String?   // 实时日志尾部，供 UI 展示真实输出
  ```
- `downloadSpeed` / `estimatedTime` 字段保留，语义改为"实况文本"。

### 3. `DeskMate/ViewModels/OnboardingViewModel.swift`（核心重写）

**3.1 新增私有状态（类属性区，约第 19 行后）**
```swift
private var installProcess: Process?
private let installProcessLock = NSLock()
private var isInstallCancelled = false
private let isInstallCancelledLock = NSLock()
private var installMilestone: Double = 0.0   // 单调递增的 milestone 进度
```
配套 `setInstallProcess` / `getInstallProcess` / `setCancelled` / `getCancelled` 线程安全访问器。

**3.2 `startInstallation(mirrorUrl:)`（第 680 行）** — 保留入口签名与状态重置；额外 `setCancelled(false)`、`installMilestone = 0.0`、`setInstallProcess(nil)`；仍调 `startSlowDownloadDetection()`；后台启动 `runInstallation`（改 async，见 3.6）。

**3.3 重写 `runInstallation(mirrorUrl:)`（第 713-886 行）为 async**，骨架：
```swift
private func runInstallation(mirrorUrl: String?) async {
    let hermesHome = resolveHermesHome()

    // 阶段 0：已安装则跳过（保留现有自动跳过）
    reportMilestone(0.05, stage: "正在检查前置依赖...", item: "检测 Hermes 是否已安装")
    if checkHermes(hermesHome: hermesHome).installed {
        // 主线程：progress=1.0, isInstalling=false, hermesInstalled=true; startEnvironmentCheck()
        return
    }

    // 阶段 1：官方脚本要求 git 可用
    let gitOk = !runShell("git --version 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    guard gitOk else { failInstall("未检测到 git。请先在终端运行 xcode-select --install 安装 Xcode Command Line Tools 后重试。"); return }
    reportMilestone(0.10, stage: "准备官方安装脚本", item: "git 已就绪 ✓")

    // 阶段 2：构造镜像环境（进程级 git insteadOf，非全局 config）
    var env = ProcessInfo.processInfo.environment
    if let mirror = mirrorUrl, !mirror.isEmpty {
        env["GIT_CONFIG_COUNT"] = "1"
        env["GIT_CONFIG_KEY_0"] = "url.\(mirror)/https://github.com/.insteadOf"
        env["GIT_CONFIG_VALUE_0"] = "https://github.com/"
    }

    // 阶段 3：流式运行官方安装脚本（< /dev/null 让交互式 prompt 直接 EOF）
    reportMilestone(0.15, stage: "正在运行官方安装脚本", item: "拉取并执行 install.sh")
    let argv = "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup < /dev/null"
    do {
        let result = try await StreamingProcessRunner.run(
            executable: "/bin/bash", args: ["-c", argv],
            environment: env, timeout: 30 * 60, logName: "OnboardingViewModel",
            onOutput: { [weak self] tail in self?.handleInstallOutput(tail) },
            onProcessReady: { [weak self] proc in self?.setInstallProcess(proc) }
        )
        setInstallProcess(nil)
        finishInstall(result: result, hermesHome: hermesHome)
    } catch {
        setInstallProcess(nil)
        failInstall("启动安装脚本失败：\(error.localizedDescription)")
    }
}
```
> `--skip-setup` 标志需在首次真机验证时对照 install.sh 实际支持的参数校准；若不支持则去掉，仅靠 `< /dev/null` 让脚本的 tty 检测走非交互路径。第 3 步 onboarding 负责模型配置，不依赖 install.sh 的 `hermes setup`。

**3.4 新增 `handleInstallOutput(_ tail: String)`**（替代 `reportProgress` 的 sleep 步进）
- 在 OutputTicker 后台队列触发；先 `stripANSI`，按行拆分。
- 取最后一条非空行 → 主线程赋值 `currentDownloadingItem`。
- 逐行匹配下方关键字表，`newMilestone = max(installMilestone, hit)`，单调递增。
- 主线程更新：`downloadProgress`、`installStageLabel`（按档位中文阶段名）、`currentDownloadingItem`、`installLogTail = lastNonEmptyLines(tail, max: 8)`、`downloadSpeed = "实时安装中"`、`estimatedTime = "已用 \(Int(elapsed))s"`。
- 进度越过 `kSlowDownloadProgressThreshold` 时 invalidate `slowDownloadTimer`。
- **删除 `Thread.sleep`**。

**进度关键字映射表**（ANSI 剥离后，大小写不敏感，单调递增）：
| 关键字（任一命中） | 进度 | 阶段 |
|---|---|---|
| `cloning` / `git clone` / `download hermes` / `repository` | 0.15 | git clone 仓库 |
| `venv` / `virtual environment` / `uv` / `python 3.11` | 0.40 | venv / uv 装 Python |
| `pip` / `installing` / `dependencies` | 0.70 | python 依赖 |
| `node` / `playwright` / `browser` / `ripgrep` / `ffmpeg` / `npm` | 0.85 | node/浏览器工具依赖 |
| `complete`(含 install/hermes) / `symlink` / `added to path` / `✓ hermes` | 0.95 | path/config 收尾 |
| 退出码 0 且 `checkHermes().installed` | 1.0 | 验证通过 |

不匹配的行：仅更新 `currentDownloadingItem` 与 `installLogTail`，进度保持上一档。首次真机跑通后用抓到的完整输出校准关键字。

**3.5 新增 `finishInstall(result:hermesHome:)` 与 `failInstall(_:)`**
```swift
private func finishInstall(result: StreamingProcessRunner.Result, hermesHome: String) {
    if getCancelled() { DispatchQueue.main.async { self.resetInstallState() }; return }
    if result.exitCode == 0 {
        let installed = checkHermes(hermesHome: hermesHome).installed
        if installed {
            DispatchQueue.main.async {
                self.slowDownloadTimer?.invalidate()
                self.model.downloadProgress = 1.0
                self.model.isInstalling = false
                self.model.installStageLabel = "安装完成 ✓"
                self.model.hermesInstalled = true
                self.model.currentDownloadingItem = nil
                self.startEnvironmentCheck()   // 保留：刷新环境状态
            }
            return
        }
        failInstall("安装脚本退出码为 0，但未检测到 hermes 可执行文件。\n\(Self.tailOf(result))")
    } else {
        failInstall("安装失败（退出码 \(result.exitCode)）。\n\(Self.tailOf(result))")
    }
}

private func failInstall(_ message: String) {
    DispatchQueue.main.async {
        self.slowDownloadTimer?.invalidate()
        self.model.isInstalling = false
        self.model.isInstallFailed = true
        self.model.installError = message
        self.model.installStageLabel = "安装失败"
        self.model.downloadSpeed = "安装失败"
        // 不置 downloadProgress = 1.0，保留当前 milestone（< 1.0）→ canAdvance=false
    }
}
```
`tailOf(result)` 取 stdout+stderr 末尾 ~10 行作为错误上下文。

**3.6 `runInstallation` 改 async**：`startInstallation` 里用 `Task { await self.runInstallation(mirrorUrl: mirrorUrl) }` 调用，避免内层 Task 嵌套。

**3.7 重写 `reportProgress` → `reportMilestone`**：去掉 `speedStr = item`、去掉 `Thread.sleep(0.3)`、去掉假 ETA 公式；仅主线程更新 `downloadProgress`（单调保护）、`installStageLabel`、`currentDownloadingItem`、`downloadSpeed="实时安装中"`、`estimatedTime="已用 Ns"`；保留"进度超阈值则取消慢速检测"分支。

**3.8 `cancelDownload()`（第 989 行）增强**：`setCancelled(true)` + `getInstallProcess()?.terminate()` 真正杀掉 install.sh 子进程；主线程 `isInstallFailed = true` + `installError = "安装已取消，可点击重试重新开始。"`，复用错误横幅的"重试"按钮（避免取消后卡死无按钮）。

**3.9 `retryInstallation()`（第 1001 行）**：保留，额外 `setCancelled(false)`、`installMilestone = 0.0`、`setInstallProcess(nil)`，再 `startInstallation(mirrorUrl:)`。

**3.10 `configureMirrorAndRestart()` / `dismissMirrorPrompt()`**：不变（镜像现在通过 env 注入新流程，UI 与触发逻辑保留）。

**3.11 保留 `runShell`（第 658 行）**：仅供 `checkHermes`/`checkPython`/`git --version` 等短同步检测；安装本身走流式 runner。

### 4. `DeskMate/Views/Onboarding/InstallEngineStepView.swift`
- 第 288 行 `Text("下载速度: \(speed) · 预计剩余时间: \(eta)")` → 改为 `Text("状态: \(speed) · \(eta)")`，去掉"下载速度/预计剩余时间"误导词。
- 进度条下方、Fun fact 上方新增**实时日志区**：当 `installLogTail` 非空时渲染等宽字体多行 `Text`（`lineLimit(6)` + `.minimumScaleFactor(0.8)`，浅灰圆角背景），让用户看到真实输出，彻底替代"假进度条"观感。新增 `let installLogTail: String?` 入参。
- 镜像相关 UI（`mirrorPromptBanner` / `mirrorActiveBanner` / `mirrorConfiguringBanner`）全部不动。
- `currentDownloadingItem` 气泡（第 233-251 行）保留。

### 5. `DeskMate/Views/Onboarding/OnboardingView.swift`
- 第 157 行 `else if state.currentStep == 1 && state.downloadProgress >= 1.0` → 加失败守卫：
  ```swift
  else if state.currentStep == 1 && state.downloadProgress >= 1.0 && !state.isInstallFailed {
      viewModel.nextStep()
  }
  ```
- 第 39 行 `if viewModel.model.isInstallFailed && viewModel.model.currentStep == 1`：**核对正确**（step index 1 即安装步骤），横幅当前不显示的真正原因是 `isInstallFailed` 从未被置真，修复后自然出现，无需改。
- 第 90-103 行 `InstallEngineStepView(...)` 调用补传 `installLogTail: viewModel.model.installLogTail`。

## 镜像注入正确性
- `GIT_CONFIG_COUNT=1` + `GIT_CONFIG_KEY_0=url.<mirror>/https://github.com/.insteadOf` + `GIT_CONFIG_VALUE_0=https://github.com/`：git ≥2.31 支持的进程级配置，把 `https://github.com/...` 重写为 `<mirror>/https://github.com/...`，仅作用于 install.sh 子进程及其 git 子进程，**不写入 `~/.gitconfig`**。
- install.sh 本身由 curl 从 `hermes-agent.nousresearch.com`（非 GitHub）拉取，国内可达；只有脚本内部 `git clone github.com/NousResearch/hermes-agent` 走镜像。uv/pip/npm 仍走各自官方源，不受影响。
- `kDefaultGithubMirror = "https://ghp.ci"`（OnboardingModel 第 5 行）直接复用。

## 涉及文件
- 新增：`DeskMate/Utils/StreamingProcessRunner.swift`
- 改：`DeskMate/ViewModels/OnboardingViewModel.swift`（核心）
- 改：`DeskMate/Models/OnboardingModel.swift`（canAdvance 守卫 + installLogTail 字段）
- 改：`DeskMate/Views/Onboarding/InstallEngineStepView.swift`（日志区 + 文案）
- 改：`DeskMate/Views/Onboarding/OnboardingView.swift`（handleNext 守卫 + 传参）
- 不动：`DeskMate/Services/OpenVikingProvider.swift`（复用其 internal helper 类，不重构）

## 验证方案

### 编译/静态
- 编译通过；`canAdvance` step 1 在 `isInstallFailed=true` 时返回 false，在 `downloadProgress=1.0 && !isInstallFailed && !isInstalling` 时返回 true。

### 干净机器（无 `~/.hermes`）
1. 删除 `~/.hermes`、`~/.local/bin/hermes`，确保 `git --version` 可用。
2. 启动 app，onboarding 第 2 步点"下一步"触发 `startInstallation()`。
3. 观察：进度 0.05→0.10→0.15→随日志关键字推进 0.40/0.70/0.85/0.95；`currentDownloadingItem` 与日志区显示真实 install.sh 输出；`downloadSpeed` 显示"实时安装中"。
4. 脚本结束 `checkHermes()` 检出 `~/.hermes/hermes-agent/hermes` 或 `~/.local/bin/hermes`，进度跳 1.0，自动进第 3 步。
5. 重启 app：`startEnvironmentCheck` 检出已安装+已配置 → `didCompleteEarly` 直进首页。

### 已安装机器
- `~/.hermes` 已存在且 hermes 可执行：`runInstallation` 阶段 0 命中跳过，进度 1.0，不应再跑 install.sh。

### 失败路径
- 断网/封 GitHub（不配镜像）：install.sh git clone 失败 → `set -e` 退出码非 0 → `failInstall` → `isInstallFailed=true`、进度停留 < 1.0、错误横幅出现、"下一步"禁用。点"重试"→ `retryInstallation` 重跑。
- 退出码 0 但 hermes 未生成：触发 `failInstall("退出码 0 但未检测到 hermes...")`。

### 镜像路径
- 限速 GitHub，15s 后 `slowDownloadTimer` 触发镜像横幅 → 点"配置镜像加速" → `configureMirrorAndRestart` → `startInstallation(mirrorUrl: "https://ghp.ci")` → 子进程 env 含 `GIT_CONFIG_*` → 用 Console.app 或日志确认 git clone URL 被重写为 `https://ghp.ci/https://github.com/NousResearch/hermes-agent.git` → 安装成功。确认 `git config --global --list` 无 insteadOf（未污染全局）。

### 取消路径
- 安装中点"取消安装"：`installProcess?.terminate()` 杀掉 install.sh；`isInstallFailed=true` + "安装已取消"；横幅"重试"可重新开始。

### 关键字表校准
- 首次真机跑通后，从 `StreamingProcessRunner.Result` 与 DMLogger heartbeat 抓出完整输出，逐行核对关键字是否覆盖各阶段；单调递增保证即使漏匹配也不回退。
