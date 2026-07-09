# WorkspaceExplorer 向 Cursor/Trae 式 diff 体验补齐 — 实现计划

## 1. 目标与范围

在上一次已实现「不依赖 Git 也能逐行审查 diff」的基础上，继续补齐三层 Cursor/Trae 标志性体验：

1. **跨会话本地历史（Local History）**：关闭项目后再打开，仍能查看并恢复到任意历史版本。
2. **文件树变更徽标（File Tree Badges）**：左侧文件树中显示 modified / added / deleted 状态点。
3. **编辑器内变更标记（Editor Gutter Markers）**：在代码编辑器行号旁显示红/绿/黄 gutter 条，标识当前内容相对于基线的变更。

**保持现有能力不变**：Git 仓库内的 diff 行为、暂存逻辑、Git 状态提示、现有 DiffReviewView 全部保留。

## 2. 当前状态分析

- `FileTab.baselineContent` 已在内存中保存「文件打开时的磁盘内容」，作为无 Git diff 的基线。
- `TextDiffer` + `DiffParser` 已能生成标准 unified diff 并渲染到 `DiffReviewView`。
- `DiffReviewViewModel` 已支持 `.git` 与 `.local` 两种 `DiffSource`。
- `LocalHistoryStore` 已实现跨会话快照持久化，`WorkspaceFileStatusProvider` 已实现 Git/非 Git 文件状态计算，`FileTreeView` 已显示状态徽标。
- `TextDiffer.lineMarkers(old:new:)` 与 `EditorDiffGutterView` 已实现 marker 计算与绘制。
- `CodeEditorView` 基于 `CodeEditSourceEditor.SourceEditor`（SwiftUI），底层可通过 `TextViewCoordinator` 访问 `TextViewController.textView`。
- **当前剩余工作**：将 `EditorDiffGutterView` 通过 `DiffGutterCoordinator` 接入 `CodeEditorView`，并在 `SimpleCodeEditor` 降级方案中同样实现 marker。

## 3. 核心设计决策

| 决策项 | 结论 |
|---|---|
| 基线来源 | 优先使用 `FileTab.baselineContent`；未打开文件使用 `LocalHistoryStore` 最新快照；无快照则视为以当前磁盘内容为基线。 |
| 本地历史存储位置 | `~/Library/Application Support/DeskMate/local-history/<workspace-hash>/<relative-path>/<timestamp>.json`，参考 `MemoryFileStore` 文件持久化模式。 |
| 快照保留策略 | 单文件最多保留 50 个快照，或最近 30 天，超出时清理最旧快照。 |
| 文件树状态 | Git 仓库走 `GitCommandService.status`；非 Git 仓库比较磁盘内容与最新快照。 |
| 编辑器 gutter | 通过 `TextViewCoordinator` 访问底层 `NSTextView`，添加覆盖视图绘制变更条；`SimpleCodeEditor`（NSTextView 降级方案）中同样实现。 |
| diff 粒度 | 行级：新增行绿色、修改行黄色、删除行红色箭头/条。 |

## 4. 新增 / 修改文件

### 4.1 跨会话本地历史

#### 新增：`DeskMate/Services/LocalHistoryStore.swift`

- 数据模型：
  ```swift
  struct LocalHistorySnapshot: Codable, Identifiable {
      let id: UUID
      let filePath: String          // 工作区相对路径
      let workspacePath: String     // 工作区绝对路径
      let timestamp: Date
      let content: String
      let source: LocalHistorySource // .diskOpen / .save / .diffApply / .periodic
  }

  enum LocalHistorySource: String, Codable {
      case diskOpen, save, diffApply, periodic
  }
  ```
- 目录组织：
  ```
  ~/Library/Application Support/DeskMate/local-history/
    <workspace-hash-sha256-8>/
      <relative-path-escaped>/
        <iso-timestamp>.json
  ```
- 公共 API：
  ```swift
  func saveSnapshot(workspace: String, filePath: String, content: String, source: LocalHistorySource)
  func latestSnapshot(workspace: String, filePath: String) -> LocalHistorySnapshot?
  func listSnapshots(workspace: String, filePath: String) -> [LocalHistorySnapshot]
  func restoreSnapshot(id: UUID) -> String?
  func deleteSnapshot(id: UUID)
  func cleanup(keepingMax: Int = 50, maxAge: TimeInterval = 30 * 24 * 60 * 60)
  ```
- 写入时机：
  - `WorkspaceExplorerView.openFileInNewTab`：文件打开时保存 `.diskOpen` 快照（若与最新快照不同）。
  - `CodeEditorView.saveFile`：保存成功后保存 `.save` 快照。
  - `WorkspaceExplorerView.applyDiffResult`：diff 应用后保存 `.diffApply` 快照。
  - 周期性：在 `WorkspaceExplorerView` 中启动一个 30 秒定时器，仅对 dirty 的编辑标签保存 `.periodic` 快照（去重）。

#### 修改：`DeskMate/Views/WorkspaceExplorer/WorkspaceExplorerView.swift`

- 在 `openFileInNewTab` 中调用 `LocalHistoryStore.saveSnapshot(..., source: .diskOpen)`。
- 在 `applyDiffResult` 中调用 `LocalHistoryStore.saveSnapshot(..., source: .diffApply)`。
- 启动一个 `Timer` / `Task` 每 30 秒对 dirty 标签保存 `.periodic` 快照。
- 关闭窗口时清理过期快照（调用 `cleanup`）。

#### 修改：`DeskMate/Views/WorkspaceExplorer/CodeEditorView.swift`

- 在 `saveFile()` 成功后调用 `onSave` 并保存 `.save` 快照。
- （可选）在 header 或 status bar 增加「历史」按钮，后续可打开历史面板。

### 4.2 文件树变更徽标

#### 新增：`DeskMate/Services/WorkspaceFileStatusProvider.swift`

- 定义状态：
  ```swift
  enum WorkspaceFileStatus: Equatable {
      case unchanged
      case modified
      case added
      case deleted
      case ignored
  }
  ```
- 核心方法：
  ```swift
  func status(for url: URL, in workspace: String) async -> WorkspaceFileStatus
  func statuses(in workspace: String) async -> [String: WorkspaceFileStatus]
  ```
- Git 仓库：调用 `GitCommandService.status()`，解析 two-letter code 映射到 `.modified` / `.added` / `.deleted`。
- 非 Git 仓库：
  - 若文件在 `openTabs` 中且 `isDirty` → `.modified`。
  - 否则读取磁盘内容，与 `LocalHistoryStore.latestSnapshot` 比较；不同则 `.modified`，相同则 `.unchanged`。
  - 文件不存在但存在快照 → `.deleted`。
  - 存在快照但文件不存在 → `.deleted`。
  - 无快照且文件存在 → `.unchanged`（首次见到）。

#### 修改：`DeskMate/Views/WorkspaceExplorer/FileNode.swift`（当前内嵌在 WorkspaceExplorerView.swift 底部）

- 给 `FileNode` 增加 `var status: WorkspaceFileStatus = .unchanged`。

#### 修改：`DeskMate/Views/WorkspaceExplorer/FileTreeView.swift`

- 在 `fileRow` 的文件名右侧增加状态徽标：
  - `.modified`：黄色/橙色圆点。
  - `.added`：绿色圆点。
  - `.deleted`：红色圆点或文件名变灰加删除线。
  - `.unchanged`：不显示。
- 目录行显示聚合状态：若子节点有任何变更，目录显示对应颜色圆点。

#### 修改：`DeskMate/Views/WorkspaceExplorer/WorkspaceExplorerView.swift`

- 在 `loadFileTree()` 完成后异步刷新所有节点状态。
- 监听编辑标签的 `content` / `isDirty` 变化，刷新对应节点状态。
- 每 5 秒后台刷新一次全部状态（捕获外部修改）。
- 在 `applyDiffResult` 后刷新状态。

### 4.3 编辑器内变更标记

#### 已完成：`DeskMate/Views/WorkspaceExplorer/EditorDiffGutterView.swift`（AppKit NSView）

- 一个透明的 `NSView`，位于编辑器左侧（覆盖在 gutter 之上或作为 editor 的 subview）。
- `draw(_:)` 中根据 `TextDiffer.LineDiffMarker` 绘制：
  - 新增：左侧 3pt 绿色竖条。
  - 修改：左侧 3pt 黄色竖条。
  - 删除：在对应行位置绘制 3pt 红色条。
- 提供 `update(markers: [TextDiffer.LineDiffMarker])` 方法触发重绘。
- 行号映射：使用 `layoutManager.boundingRect(forGlyphRange:in:)` 将 0-based 行号转换为视图坐标。

#### 新增：`DeskMate/Views/WorkspaceExplorer/DiffGutterCoordinator.swift`

- 实现 `CodeEditSourceEditor.TextViewCoordinator`：
  ```swift
  final class DiffGutterCoordinator: TextViewCoordinator {
      private var markerView: EditorDiffGutterView?
      private var baseContent: String = ""
      private var scrollObserver: Any?

      func setBaseContent(_ content: String) {
          baseContent = content
          markerView?.update(markers: computeMarkers())
      }

      func prepareCoordinator(controller: TextViewController) {
          // 将 markerView 添加到 gutterView 上，gutter 是 scroll view 的 horizontal floating ruler，
          // 会随文本垂直滚动自动对齐，且水平滚动时保持可见。
          let markerView = EditorDiffGutterView(frame: .zero)
          markerView.autoresizingMask = [.width, .height]
          markerView.textView = controller.textView
          controller.gutterView.addSubview(markerView)
          self.markerView = markerView

          // 监听垂直滚动，重绘 marker
          scrollObserver = NotificationCenter.default.addObserver(
              forName: NSView.boundsDidChangeNotification,
              object: controller.scrollView.contentView,
              queue: .main
          ) { [weak self] _ in
              self?.markerView?.setNeedsDisplay(self?.markerView?.bounds ?? .zero)
          }

          updateMarkers(controller: controller)
      }

      func textViewDidChangeText(controller: TextViewController) {
          updateMarkers(controller: controller)
      }

      func destroy() {
          if let observer = scrollObserver {
              NotificationCenter.default.removeObserver(observer)
              scrollObserver = nil
          }
          markerView?.removeFromSuperview()
          markerView = nil
      }

      private func updateMarkers(controller: TextViewController) {
          markerView?.update(markers: TextDiffer.lineMarkers(old: baseContent, new: controller.text))
      }
  }
  ```
- Marker 位置计算：在 `EditorDiffGutterView.draw(_:)` 中通过 `layoutManager.boundingRect(forGlyphRange:in:)` 将行号映射为 y 坐标，与 gutter 行号对齐。
- 注意 `SourceEditor` 的初始化器支持 `coordinators: [any TextViewCoordinator]` 参数。

#### 修改：`DeskMate/Views/WorkspaceExplorer/CodeEditorView.swift`

- 增加 `baselineContent: String` 参数（默认空字符串）。
- 创建 `DiffGutterCoordinator` 实例并持有在 `State` 中：
  ```swift
  @State private var diffGutterCoordinator = DiffGutterCoordinator()
  ```
- `SourceEditor` 初始化器增加 `coordinators: [diffGutterCoordinator]`。
- 在 `onAppear` 或当 `baselineContent` 变化时调用 `diffGutterCoordinator.setBaseContent(baselineContent)`。
- `SimpleCodeEditor`（fallback）也添加 gutter marker 绘制：
  - 在 `makeNSView` 中创建 `EditorDiffGutterView`，作为 `scrollView` 的 subview 或在 `textView` 左侧固定位置；绑定 `textView` 并传入初始 markers。
  - 在 `updateNSView` 中当 `text` 变化时更新 markers。
  - 在 `Coordinator.textDidChange(_:)` 中更新 markers。

#### 修改：`DeskMate/Views/WorkspaceExplorer/WorkspaceExplorerView.swift`

- 给 `CodeEditorView` 传入 `baselineContent: active.baselineContent`。
- 当 `applyDiffResult` 更新 `baselineContent` 后，gutter 自动重新计算（因为 baselineContent 绑定会变化）。

## 5. 关键边界场景

| 场景 | 行为 |
|---|---|
| 非 Git 目录首次打开文件 | 保存 `.diskOpen` 快照；文件树显示 `.unchanged`；编辑器无 gutter 标记。 |
| 用户编辑文件 | gutter 实时显示新增/修改行；文件树显示 `.modified`；每 30 秒保存 `.periodic` 快照。 |
| 用户保存文件 | 保存 `.save` 快照；`baselineContent` 更新；gutter 清空；文件树恢复 `.unchanged`。 |
| 用户在 DiffReviewView 中部分接受 | 重建内容写回磁盘；保存 `.diffApply` 快照；编辑器 content/baseline 同步；gutter 刷新。 |
| 外部程序修改文件 | 5 秒定时刷新文件树状态；若文件未打开则显示 `.modified`；已打开文件以编辑器内 baseline 为准。 |
| 文件被外部删除 | 文件树显示 `.deleted`；若存在快照可恢复。 |
| Git 仓库 | 文件树状态全部来自 `git status`；本地历史作为附加备份，不影响现有 Git diff 流程。 |
| 大文件 | diff 计算在主线程外进行；gutter 更新切回主线程。 |

## 6. 实施顺序

1. **LocalHistoryStore 实现与集成**：先完成快照持久化，验证打开/保存/diff apply 都能正确写入。
2. **WorkspaceFileStatusProvider + 文件树徽标**：实现状态计算并刷新 UI。
3. **EditorDiffGutter + DiffGutterCoordinator**：实现编辑器 gutter 标记，优先在 `SimpleCodeEditor` 验证逻辑，再接入 `CodeEditSourceEditor`。
4. **端到端验证**：非 Git 目录编辑、保存、diff 接受/拒绝、外部修改、关闭重开项目。
5. **Git 仓库回归验证**：确保原有 diff / 暂存 / 状态不受新功能影响。

## 7. 验证标准

- [ ] 非 Git 目录中编辑文件后关闭窗口，重新打开项目，能在 Local History 中看到历史快照并恢复。
- [ ] 文件树中能正确显示 modified / added / deleted 徽标（Git 与非 Git 目录均验证）。
- [ ] 编辑器左侧 gutter 显示绿色（新增）、黄色（修改）、红色（删除）标记。
- [ ] 保存文件后 gutter 清空，文件树状态恢复。
- [ ] DiffReviewView 接受/拒绝后，编辑器 gutter 与文件树状态同步刷新。
- [ ] Git 仓库内原有 diff 行为、暂存、状态提示保持不变。
- [ ] Xcode Build 无新增错误，无与本次改动相关的警告。
