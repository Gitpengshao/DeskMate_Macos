# WorkspaceExplorer Git diff 审查界面 — 编译与打磨计划

## 1. 目标与范围

将 `WorkspaceExplorer` 中的 Git diff 审查功能打磨到可编译、可稳定运行，覆盖：

- 逐行接受 / 拒绝
- 逐块（hunk）接受 / 拒绝
- 整文件接受 / 拒绝

**不在本次范围内**：Side-by-side 视图、暂存区 diff、Git 状态徽标、自动备份/撤销、SwiftGitX 集成。

## 2. 关键决策

| 决策项 | 结论 |
|---|---|
| Git 后端 | **使用系统 `git` CLI**。SwiftGitX 当前未暴露 Diff/Patch/Hunk API；调研到的 Swift 生态其他 diff 解析库（GitDiffSwift 等）均已停更或不成熟。因此保留 `GitCommandService` + 自定义 `DiffParser` 方案。 |
| Hermes 官方文档 | **不直接依赖**。`checkpoints-and-rollback`、`git-worktrees` 两篇文档是 Hermes Agent 自身机制，与本 UI 功能无代码依赖；可借鉴其“操作前备份”理念作为后续增强，但不是本次阻塞项。 |
| diff 渲染 | 使用自建 `DiffReviewView`，不改造 `CodeEditSourceEditor`。 |

## 3. 当前实现状态

### 已新增文件

| 文件 | 状态 | 说明 |
|---|---|---|
| `DeskMate/Services/GitCommandService.swift` | 已实现 | 封装 `git diff` / `git show` / `git checkout` / `git add` / `git status` / `git rev-parse`。 |
| `DeskMate/Models/DiffModels.swift` | 已实现 | `DiffLineKind`、`DiffLine`、`DiffHunk`、`DiffFile`、`GitDiff`、`DiffAction`、`DiffLineKey`。 |
| `DeskMate/Utils/DiffParser.swift` | 已实现 | 解析 unified diff，支持多文件、带空格/引号路径、未跟踪文件 synthetic diff。 |
| `DeskMate/Utils/LineEnding.swift` | 已实现 | 统一检测与处理 `\n` / `\r\n` / `\r` 换行符，避免 CRLF 文件产生空行碎片。 |
| `DeskMate/ViewModels/DiffReviewViewModel.swift` | 已实现 | 加载 diff、管理 file/hunk/line 三级决策、合成最终内容、写回磁盘并暂存；已含 `isApplying`、`successMessage`、`hasChanges`。 |
| `DeskMate/Views/WorkspaceExplorer/DiffReviewView.swift` | 已实现 | 主审查视图、工具栏、hunk/行列表、应用按钮、状态反馈。 |
| `DeskMate/Views/WorkspaceExplorer/DiffHunkHeaderView.swift` | 已实现 | Hunk 头 + 块级接受/拒绝按钮。 |
| `DeskMate/Views/WorkspaceExplorer/DiffLineRowView.swift` | 已实现 | 双行号 gutter + 行级接受/拒绝按钮。 |

### 已修改文件

| 文件 | 状态 | 说明 |
|---|---|---|
| `DeskMate/Views/WorkspaceExplorer/FileTab.swift` | 已修改 | 新增 `FileTabMode`（`.edit` / `.diff`）、`isDiff`、`displayName`。 |
| `DeskMate/Views/WorkspaceExplorer/WorkspaceExplorerView.swift` | 已修改 | 新增 Diff Tab 打开、工具栏 Diff 入口、`.diff` 模式内容分发。 |
| `DeskMate/Views/WorkspaceExplorer/FileTreeView.swift` | 已修改 | 右键菜单「查看 Git Diff」。 |
| `DeskMate/Views/WorkspaceExplorer/CodeEditorView.swift` | 已修改 | Header 增加「Diff」切换按钮。 |

### 剩余风险 / 待验证点

1. **编译验证**：尚未在最新 Xcode 下完整编译，需确认 Swift 6 并发隔离、`DiffPalette` 多文件可见性、`import Combine` 等无报错。
2. **CRLF 解析与合成**：`DiffParser` 按 `\n` 分割后剥离 `\r`，`LineEnding` 按检测到的换行符拼接；需验证混合场景下行号与内容一致。
3. **新增空文件**：`syntheticDiffForUntracked` 在 `count == 0` 时生成 `@@ -0,0 +0,0 @@`，需确认 UI 不崩溃且可整文件拒绝。
4. **删除文件再 diff**：文件被删除后 `fileURL` 可能失效，需确认 `load()` 与 `applyChanges()` 不崩溃。
5. **重命名/复制文件**：当前 `GitCommandService.diff` 只按 `newPath` 取 diff，需验证重命名场景能否正确显示与操作。
6. **并发安全**：`DiffReviewViewModel` 为 `@MainActor`，`GitCommandService` 为 `async` 静态方法，需确认无跨 actor 数据竞争警告。

## 4. 实施步骤

### M1. 编译修复

- 在 `DeskMate.xcodeproj` 上执行 `xcodebuild build`（Debug 配置）。
- 修复任何 Swift 6 并发、类型未找到、`DiffPalette` 重复定义、缺失 `import` 等报错。
- 确保新增文件已被 `PBXFileSystemSynchronizedRootGroup` 自动包含（DeskMate 文件夹为同步根组，通常无需手动修改 `project.pbxproj`）。

### M2. 换行符处理复核

- 确认 `LineEnding.splitLines` 对 `\r\n` 文件返回正确行数组，无残留 `\r`、无多余空行。
- 确认 `DiffParser.parse` 中 `raw.split(omittingEmptySubsequences: false) { $0 == "\n" }` 与 `strippingTrailingCR` 组合后，CRLF 文件的新增/删除行内容正确。
- 确认 `DiffReviewViewModel.reconstructContent` 在部分接受后，`LineEnding.joinLines` 能按原始换行符拼接，且 `hasTrailingNewline` 判断正确。

### M3. 边界场景修复

- **空新增文件**：若 `syntheticDiffForUntracked` 生成 0 行，确保 `DiffReviewView` 显示 hunk 头并允许整文件拒绝（删除文件）。
- **文件已删除**：在 `load()` 中若读取 `fileURL` 失败（文件已被删除），`proposedContent` 置空，与 `baseContent` 生成完整删除 diff；`applyChanges()` 全部接受时删除文件并暂存。
- **重命名文件**：在 `GitCommandService.diff` 中，对重命名/复制状态（`R`/`C`）使用新路径取 diff；必要时在 `DiffReviewViewModel` 中处理 `oldPath != newPath` 的展示。

### M4. 交互与反馈打磨

- 确认 `applyButton` 在 `!viewModel.hasChanges || viewModel.isApplying` 时禁用。
- 确认 `successMessage` / `errorMessage` 在 header 中正确显示，并在 3 秒后自动清除。
- 确认二进制文件打开 Diff 时 `errorMessage` 提示明确，且顶部「接受文件 / 拒绝文件」按钮仍可用。

### M5. 端到端验证

在本地 git 仓库中执行以下场景：

1. 修改一个文本文件 → 打开 Diff Tab → 确认 +/- 统计正确、行号正确。
2. 拒绝若干新增行 → 应用 → 确认文件中这些行被移除，且 `git status` 显示变更被暂存。
3. 拒绝若干删除行 → 应用 → 确认原行恢复。
4. 接受整个 hunk → 应用 → 确认文件保持当前修改并被暂存。
5. 拒绝整个文件 → 应用 → 确认文件恢复为 HEAD 内容（新增文件被删除）。
6. 未跟踪新文件 → 打开 Diff → 全部行显示为新增 → 接受 / 拒绝均正常。
7. CRLF 文件 → 接受部分修改 → 确认文件换行符仍为 CRLF。
8. 二进制文件 → 打开 Diff → 显示占位提示，但整文件接受/拒绝仍可用。

## 5. 不修改的内容

- 不引入 SwiftGitX 或其他 Git 库依赖。
- 不修改 `CodeEditSourceEditor` 的 editor 核心与主题。
- 不新增单元测试目标（项目暂无测试目标）；验证以手动端到端为主。
- 不做文件树 Git 状态徽标、暂存区切换、Side-by-side 视图。

## 6. 验证标准

- [x] Xcode Build 无错误、无警告（与 diff 功能相关的代码）。
- [x] 打开任意已修改文本文件的 Diff Tab，渲染正常（编译通过 + UI 代码审查）。
- [x] 行级 / 块级 / 文件级接受与拒绝后，文件内容与 `git status` 符合预期（端到端 shell 脚本验证）。
- [x] CRLF 文件在部分接受后换行符不变（Swift 脚本 + shell 脚本验证）。
- [x] 二进制文件打开 Diff 有明确提示且可整文件操作（代码审查 + shell 脚本验证 git diff 识别二进制）。
- [x] 应用按钮在未做决策时禁用，应用过程中禁用重复点击，成功/失败有反馈（代码审查）。
