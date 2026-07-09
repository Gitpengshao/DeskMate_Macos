# WorkspaceExplorer 非 Git diff 审查 — 实现计划

## 1. 目标与范围

让 `WorkspaceExplorer` 的 diff 审查不再依赖 Git 仓库。无论当前目录是否 `git init`，用户点击「Diff」都能看到当前文件相对于「打开时/基线」版本的新增、删除、修改，并支持整文件 / hunk / 单行三级接受 / 拒绝。

**保持现有能力不变**：Git 仓库内的 diff 行为、暂存逻辑、Git 状态提示全部保留。

**不在本次范围内**：跨会话本地历史（Cursor 式快照）、side-by-side 视图、文件树 Git 徽标。

## 2. 核心思路

Git diff 的本质是 **old(base) vs new(current)**。无 Git 时，自己提供 base：

- 文件被打开为编辑标签时，把磁盘内容同时写入 `FileTab.baselineContent`。
- 用户编辑只改 `FileTab.content`，baseline 不变。
- 点击 Diff 时，用 `TextDiffer` 对 `baselineContent` 和 `currentContent` 做行级 diff，生成 `GitDiff` 模型。
- 接受 / 拒绝后把重建内容写回磁盘，并同步更新编辑标签的 content、baseline、dirty 状态。

## 3. 关键决策

| 决策项 | 结论 |
|---|---|
| 基线存储位置 | `FileTab.baselineContent`（内存）。最贴合当前 Tab 模型，关闭文件即释放，无需持久化设计。后续若要升级为 Cursor 式快照，只需把 baseline 来源换成磁盘历史。 |
| 无 Git diff 算法 | 新增 `TextDiffer.swift`，基于 Myers / LCS 做行级 diff，输出 unified diff 文本，再复用现有 `DiffParser.parse` 得到 `GitDiff`。视图层零改动。 |
| ViewModel 抽象 | 引入 `DiffSource`：`.git(workingDirectory)` 保持原逻辑；`.local(baseContent:proposedContent:isNew:apply:)` 走无 Git 路径。 |
| 当前内容来源 | 优先取同 URL 编辑标签的 `tab.content`（包含未保存修改）；没有编辑标签时才读磁盘。 |
| apply 回调 | `DiffSource.local` 携带 `@MainActor (String) -> Void` 回调，由 `WorkspaceExplorerView` 负责更新对应 `FileTab` 的 content/baseline/isDirty。 |

## 4. 待修改 / 新增文件

### 新增

- `DeskMate/Utils/TextDiffer.swift`
  - `TextDiffer.unifiedDiff(old:new:path:contextLines:) -> String`
  - 内部 Myers diff 或 LCS，输出标准 unified diff，兼容 `DiffParser.parse`。
  - 处理 old/new 为空、路径带空格等边界。

### 修改

- `DeskMate/Models/DiffModels.swift`
  - 新增 `DiffSource` 枚举（也可放在 ViewModel，视接口简洁性决定）。

- `DeskMate/Views/WorkspaceExplorer/FileTab.swift`
  - 增加 `var baselineContent: String`。
  - 在 `==` 中加入比较，确保 `@State` 数组能感知变化。

- `DeskMate/Views/WorkspaceExplorer/CodeEditorView.swift`
  - Diff 按钮 help 文案从「查看 Git Diff」改为「查看 Diff」。
  - 保存成功后通过新增 `onSave` 回调通知父视图更新 baseline。

- `DeskMate/Views/WorkspaceExplorer/WorkspaceExplorerView.swift`
  - `openFileInNewTab`：初始化 `FileTab` 时 `baselineContent = content`。
  - `openDiffInNewTab`：构造 `DiffSource`。
    - 若目录是 Git 仓库：沿用 `.git(workingDirectory)`。
    - 否则：查找同 URL 编辑标签，base = `tab.baselineContent`，current = `tab.content`；无编辑标签时两者都读磁盘（diff 为空，显示占位）。
  - 给 `DiffReviewView` 传入 `DiffSource` 和 apply 回调：更新 / 创建编辑标签，清 dirty，必要时删除文件或关闭标签。

- `DeskMate/ViewModels/DiffReviewViewModel.swift`
  - 用 `DiffSource` 替换原来的 `workingDirectory: String` 必填参数。
  - `load()` 分支：
    - `.git`：保持现有 Git 流程。
    - `.local`：直接赋值 `baseContent` / `proposedContent`，调用 `TextDiffer` + `DiffParser.parse`。
  - `applyChanges()` 分支：
    - `.git`：保持现有 accept / reject / 混合决策 + git staging 流程。
    - `.local`：用 `reconstructContent` 得到最终内容，直接写磁盘，调用 apply 回调；不再调用 `GitCommandService.acceptFile/rejectFile`。
  - 状态文案去 Git 化：无 Git 模式下成功提示改为「已应用」「已拒绝并还原」等。

- `DeskMate/Views/WorkspaceExplorer/DiffReviewView.swift`
  - init 改为接收 `DiffSource` 与 `fileURL`。
  - header 中帮助文案与状态提示适配无 Git 场景。

## 5. 边界场景处理

| 场景 | 行为 |
|---|---|
| 非 Git 目录文本文件被修改 | 正常显示 diff，可操作。 |
| 文件刚打开未编辑 | base == current，显示「没有可审查的修改」。 |
| 新文件（base 空，current 非空） | `TextDiffer` 生成全量新增 diff，整文件拒绝 = 删除文件。 |
| 文件被外部删除（current 空，base 非空） | 生成全量删除 diff，全部接受 = 删除文件，全部拒绝 = 恢复 base。 |
| 二进制文件 | 用 `FileType.classify` 检测，显示占位提示，仅允许整文件接受/拒绝。 |
| CRLF / LF | `LineEnding.splitLines` / `joinLines` 处理，diff 行内容不含行尾符。 |
| 无 Git 目录中从文件树直接点 Diff | 若文件未在编辑器打开，base/current 都读磁盘，diff 为空；提示用户先编辑。 |

## 6. 实施顺序

1. **TextDiffer 实现**：先写独立的 `TextDiffer.swift`，并用小脚本 / playground 验证对常见 diff 的输出能被 `DiffParser.parse` 正确解析。
2. **DiffSource 与 FileTab 改造**：新增 baseline，定义 source 枚举。
3. **DiffReviewViewModel 分支**：保持 Git 路径不动，新增 local 路径。
4. **WorkspaceExplorerView 集成**：构造 source、apply 回调、保存时更新 baseline。
5. **DiffReviewView / CodeEditorView 文案微调**。
6. **编译与端到端验证**。

## 7. 验证标准

- [ ] 非 Git 目录打开文本文件并修改 → 点击 Diff 能正确显示 +/- 行。
- [ ] 无 Git 时整文件 / hunk / 单行接受与拒绝后，磁盘内容与编辑器标签同步正确。
- [ ] 无 Git 时「拒绝文件」能把文件还原到打开时的状态；新文件则被删除。
- [ ] Git 仓库内原有 diff 行为不变，仍可正常暂存。
- [ ] 文件未修改时打开 Diff 显示「没有可审查的修改」，不报错。
- [ ] 二进制文件在非 Git 目录下打开 Diff 提示明确，且可整文件接受/拒绝。
- [ ] Xcode Build 无错误、无与 diff 相关的新增警告。
