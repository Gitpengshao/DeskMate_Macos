import Foundation
import Combine

/// 记忆管理页 ViewModel — 对齐 Flutter `MemoryManagementViewModel`（Riverpod Notifier）。
///
/// MVVM 单一状态源：所有状态通过 `model: MemoryManagementModel` 发布；
/// View 通过 `@Published` 订阅更新。所有文件 I/O 与子进程管理均为异步。
@MainActor
final class MemoryManagementViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var model: MemoryManagementModel = MemoryManagementModel()

    // MARK: - Dependencies

    private let store: MemoryFileStore
    private let provider: OpenVikingProvider
    private let pythonLocator: PythonLocator
    private let defaults: UserDefaults

    // MARK: - Init

    init(
        store: MemoryFileStore = MemoryFileStore(),
        provider: OpenVikingProvider = OpenVikingProvider(),
        pythonLocator: PythonLocator = PythonLocator(),
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.provider = provider
        self.pythonLocator = pythonLocator
        self.defaults = defaults

        // 启动时异步加载 — 对齐 Flutter `Future.microtask` 行为
        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    /// 主动销毁时停止子进程 — 对齐 Flutter `ref.onDispose`。
    func dispose() {
        Task { [provider] in
            await provider.stopProcess()
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        // 恢复上次保存的 pip 镜像源
        if let saved = defaults.string(forKey: "DeskMate.OpenViking.PipIndexUrl"),
           !saved.isEmpty {
            model.pipIndexUrl = saved
            provider.setPipIndexUrl(saved)
        }
        await resolvePython()
        await loadMemories()
        await loadUserProfile()
        await initProviderState()
    }

    // MARK: - Python interpreter

    /// 解析当前 Python 解释器并注入到 provider。
    private func resolvePython() async {
        let path = await pythonLocator.resolvePythonPath()
        model.pythonPath = path
        if let path {
            provider.setPythonPath(path)
            DMLogger.log(
                "PythonLocator: resolved python @ \(path)",
                name: "MemoryManagementVM"
            )
        } else {
            DMLogger.error(
                "PythonLocator: no usable python interpreter found",
                name: "MemoryManagementVM"
            )
        }
    }

    /// 弹出"选择 Python 解释器"对话框前先扫描一次。
    func showPythonPicker() {
        model.isShowingPythonPicker = true
        Task { [weak self] in
            await self?.rescanPythonCandidates()
        }
    }

    /// 关闭 Python 选择器。
    func dismissPythonPicker() {
        model.isShowingPythonPicker = false
    }

    /// 重新扫描系统中可用的 Python 解释器。
    func rescanPythonCandidates() async {
        model.isScanningPython = true
        let candidates = await pythonLocator.discoverCandidates()
        model.pythonCandidates = candidates
        model.isScanningPython = false
    }

    /// 用户从候选列表中选了一个解释器 — 立即生效并保存。
    func selectPythonCandidate(_ candidate: PythonCandidate) {
        pythonLocator.setUserOverride(candidate.path)
        model.pythonPath = candidate.path
        provider.setPythonPath(candidate.path)
        model.isShowingPythonPicker = false
        DMLogger.log(
            "PythonLocator: user override set to \(candidate.path)",
            name: "MemoryManagementVM"
        )
    }

    /// 清除用户手动选择，恢复自动检测。
    func clearPythonOverride() {
        pythonLocator.setUserOverride(nil)
        defaults.removeObject(forKey: PythonLocator.lastAutoDetectedKey)
        Task { [weak self] in
            await self?.resolvePython()
        }
    }

    // MARK: - pip mirror

    /// 弹出 pip 镜像源编辑对话框。
    func showPipMirrorEditor() {
        model.isShowingPipMirrorEditor = true
    }

    /// 关闭 pip 镜像源编辑对话框。
    func dismissPipMirrorEditor() {
        model.isShowingPipMirrorEditor = false
    }

    /// 用户更新了 pip 镜像源 — 立即应用并保存。
    func setPipIndexUrl(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.pipIndexUrl = trimmed
        provider.setPipIndexUrl(trimmed)
        defaults.set(trimmed, forKey: "DeskMate.OpenViking.PipIndexUrl")
        DMLogger.log(
            "OpenViking: pip index url set to \(trimmed)",
            name: "MemoryManagementVM"
        )
    }

    // MARK: - Tab switching

    /// 切换 Tab — 对齐 Flutter `switchTab`。
    func switchTab(_ tab: MemoryTab) {
        DMLogger.log("MemoryMgmt: switchTab -> \(tab.rawValue)", name: "MemoryManagementVM")
        model.activeTab = tab
        model.errorMessage = nil
    }

    /// 清除错误消息。
    func clearError() {
        model.errorMessage = nil
    }

    // MARK: - Memory entries (MEMORY.md)

    /// 读取 MEMORY.md 条目。
    func loadMemories() async {
        DMLogger.log("_loadMemories: reading MEMORY.md ...", name: "MemoryManagementVM")
        model.isLoadingMemories = true
        model.errorMessage = nil
        defer { model.isLoadingMemories = false }
        do {
            let entries = try store.readEntries(.memory)
            DMLogger.log(
                "_loadMemories: got \(entries.count) entries",
                name: "MemoryManagementVM"
            )
            model.memoryEntries = entries
        } catch {
            DMLogger.error(
                "_loadMemories: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 新增一条记忆 — 对齐 Flutter `addMemoryEntry`。
    func addMemoryEntry(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        DMLogger.log("addMemoryEntry: appending to MEMORY.md ...", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.memory)
            let nextIndex = entries.isEmpty ? 0 : (entries.last?.index ?? 0) + 1
            entries.append(MemoryEntry(target: .memory, index: nextIndex, content: trimmed))
            try store.writeEntries(.memory, entries: entries)
            DMLogger.log("addMemoryEntry: saved OK", name: "MemoryManagementVM")
            await loadMemories()
        } catch {
            DMLogger.error(
                "addMemoryEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 编辑一条记忆 — 对齐 Flutter `editMemoryEntry`。
    func editMemoryEntry(_ entryId: String, newContent: String) async {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        DMLogger.log("editMemoryEntry: updating \(entryId)", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.memory)
            guard let index = indexFromId(entryId), index >= 0, index < entries.count else {
                return
            }
            entries[index] = entries[index].updatingContent(trimmed)
            try store.writeEntries(.memory, entries: entries)
            DMLogger.log("editMemoryEntry: updated OK", name: "MemoryManagementVM")
            await loadMemories()
        } catch {
            DMLogger.error(
                "editMemoryEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 删除一条记忆 — 对齐 Flutter `deleteMemoryEntry`。
    func deleteMemoryEntry(_ entryId: String) async {
        DMLogger.log("deleteMemoryEntry: deleting \(entryId)", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.memory)
            guard let index = indexFromId(entryId), index >= 0, index < entries.count else {
                return
            }
            entries.remove(at: index)
            try store.writeEntries(.memory, entries: entries)
            DMLogger.log("deleteMemoryEntry: deleted OK", name: "MemoryManagementVM")
            await loadMemories()
        } catch {
            DMLogger.error(
                "deleteMemoryEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    // MARK: - User Profile entries (USER.md)

    /// 读取 USER.md 条目。
    func loadUserProfile() async {
        DMLogger.log("_loadUserProfile: reading USER.md ...", name: "MemoryManagementVM")
        model.isLoadingUserProfile = true
        model.errorMessage = nil
        defer { model.isLoadingUserProfile = false }
        do {
            let entries = try store.readEntries(.user)
            DMLogger.log(
                "_loadUserProfile: got \(entries.count) entries",
                name: "MemoryManagementVM"
            )
            model.userProfileEntries = entries
        } catch {
            DMLogger.error(
                "_loadUserProfile: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 新增一条用户画像 — 对齐 Flutter `addUserProfileEntry`。
    func addUserProfileEntry(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        DMLogger.log("addUserProfileEntry: appending to USER.md ...", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.user)
            let nextIndex = entries.isEmpty ? 0 : (entries.last?.index ?? 0) + 1
            entries.append(MemoryEntry(target: .user, index: nextIndex, content: trimmed))
            try store.writeEntries(.user, entries: entries)
            DMLogger.log("addUserProfileEntry: saved OK", name: "MemoryManagementVM")
            await loadUserProfile()
        } catch {
            DMLogger.error(
                "addUserProfileEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 编辑一条用户画像 — 对齐 Flutter `editUserProfileEntry`。
    func editUserProfileEntry(_ entryId: String, newContent: String) async {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        DMLogger.log("editUserProfileEntry: updating \(entryId)", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.user)
            guard let index = indexFromId(entryId), index >= 0, index < entries.count else {
                return
            }
            entries[index] = entries[index].updatingContent(trimmed)
            try store.writeEntries(.user, entries: entries)
            DMLogger.log("editUserProfileEntry: updated OK", name: "MemoryManagementVM")
            await loadUserProfile()
        } catch {
            DMLogger.error(
                "editUserProfileEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    /// 删除一条用户画像 — 对齐 Flutter `deleteUserProfileEntry`。
    func deleteUserProfileEntry(_ entryId: String) async {
        DMLogger.log("deleteUserProfileEntry: deleting \(entryId)", name: "MemoryManagementVM")
        do {
            var entries = try store.readEntries(.user)
            guard let index = indexFromId(entryId), index >= 0, index < entries.count else {
                return
            }
            entries.remove(at: index)
            try store.writeEntries(.user, entries: entries)
            DMLogger.log("deleteUserProfileEntry: deleted OK", name: "MemoryManagementVM")
            await loadUserProfile()
        } catch {
            DMLogger.error(
                "deleteUserProfileEntry: error \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    // MARK: - External Provider (OpenViking)

    /// 首次加载：读取 config.yaml 决定初始状态。
    func initProviderState() async {
        DMLogger.log("OpenViking: init provider state ...", name: "MemoryManagementVM")
        let activeProvider = provider.readConfigMemoryProvider()
        DMLogger.log(
            "OpenViking: config memory.provider=\(activeProvider ?? "nil")",
            name: "MemoryManagementVM"
        )
        guard activeProvider == "openviking" else { return }

        let installed = await provider.checkInstalled()
        let running = await provider.checkHealth()
        DMLogger.log(
            "OpenViking: init — installed=\(installed) running=\(running)",
            name: "MemoryManagementVM"
        )

        model.activeProvider = .openviking
        model.providerEndpoint = "http://localhost:1933"
        model.providerStatus = running ? .running : .stopped
        model.providerStatusMessage = running ? "服务运行中" : "服务已停止"

        if !installed {
            model.providerStatus = .notInstalled
            model.providerStatusMessage = "未安装"
        }
    }

    /// 切换 OpenViking 启用状态 — 对齐 Flutter `toggleOpenViking`。
    func toggleOpenViking(_ enable: Bool) {
        if enable {
            Task { await enableOpenViking() }
        } else {
            Task { await disableOpenViking() }
        }
    }

    private func enableOpenViking() async {
        DMLogger.log("OpenViking: enable requested", name: "MemoryManagementVM")
        model.errorMessage = nil
        model.installProgressLog = ""

        // 0. 校验 Python 解释器
        if model.pythonPath == nil {
            await resolvePython()
        }
        guard let py = model.pythonPath else {
            model.providerStatus = .error
            model.providerStatusMessage = "未找到可用的 Python 解释器"
            model.errorMessage = """
            未在系统中找到可用的 Python 解释器。
            请确认已安装 Python 3.10+，或点击下方"选择 Python 解释器"手动指定。
            """
            return
        }
        DMLogger.log("OpenViking: using python @ \(py)", name: "MemoryManagementVM")

        // 把 pip 镜像源推送给 provider
        provider.setPipIndexUrl(model.pipIndexUrl)

        model.activeProvider = .openviking
        model.providerStatus = .installing
        model.providerStatusMessage = "正在安装 openviking ..."
        model.providerEndpoint = "http://localhost:1933"

        // 1. 安装检查
        let installed = await provider.checkInstalled()
        DMLogger.log("OpenViking: installed=\(installed)", name: "MemoryManagementVM")
        if !installed {
            // 实时把 pip 输出推送到 UI
            let ok = await provider.install { [weak self] tail in
                guard let self else { return }
                Task { @MainActor in
                    self.model.installProgressLog = tail
                    if !tail.isEmpty {
                        self.model.providerStatusMessage =
                            "正在安装 openviking（查看下方日志）"
                    }
                }
            }
            if !ok {
                model.providerStatus = .error
                model.providerStatusMessage = "安装失败"
                let detail = provider.lastInstallError ?? "未知错误"
                model.errorMessage = """
                OpenViking 安装失败。

                Python: \(py)
                镜像源: \(model.pipIndexUrl)
                错误详情:
                \(detail)
                """
                return
            }
        }

        // 2. 启动服务
        model.providerStatus = .installing
        model.providerStatusMessage = "正在启动 OpenViking 服务..."
        let started = await provider.startServer()
        if !started {
            model.providerStatus = .error
            model.providerStatusMessage = "启动失败"
            let detail = provider.lastStartError
                ?? "服务未在 30s 内响应健康检查"
            model.errorMessage = """
            OpenViking 启动失败。

            Python: \(py)
            错误详情:
            \(detail)
            """
            return
        }

        // 3. 写 config.yaml
        do {
            try provider.writeConfigMemoryProvider("openviking")
        } catch {
            DMLogger.error(
                "writeConfigMemoryProvider failed: \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
        }

        model.providerStatus = .running
        model.providerStatusMessage = "服务运行中"
        model.errorMessage = nil
        DMLogger.log("OpenViking: enabled and running", name: "MemoryManagementVM")
    }

    private func disableOpenViking() async {
        model.providerStatus = .stopped
        model.providerStatusMessage = "正在停止..."
        do {
            await provider.stopProcess()
            try provider.writeConfigMemoryProvider("off")
            model.activeProvider = nil
            model.providerStatus = .notInstalled
            model.providerStatusMessage = nil
            model.providerEndpoint = nil
            DMLogger.log("OpenViking: disabled", name: "MemoryManagementVM")
        } catch {
            DMLogger.error(
                "disableOpenViking: \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Public lifecycle

    /// 公开的清理入口 — 对齐 Flutter `disposeProvider`。
    func disposeProvider() async {
        await provider.stopProcess()
    }

    // MARK: - Provider WebView launcher

    /// 启动新进程打开 OpenViking WebView 窗口。
    ///
    /// 通过 `Bundle.main.executablePath` 拉起一个 DeskMate 子进程，
    /// 并附带 `--show-webview <url>` 启动参数；新进程检测到该参数后会
    /// 仅展示 `MMWebViewWindow`，关闭后自动退出（不影响主进程）。
    func openProviderWebView(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DMLogger.log(
            "OpenViking: launching new process for WebView @ \(trimmed)",
            name: "MemoryManagementVM"
        )
        guard let execPath = Bundle.main.executablePath else {
            DMLogger.error(
                "OpenViking: cannot resolve Bundle.main.executablePath",
                name: "MemoryManagementVM"
            )
            model.errorMessage = "无法启动 WebView 窗口：找不到可执行文件路径"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: execPath)
        process.arguments = ["--show-webview", trimmed]
        do {
            try process.run()
            DMLogger.log(
                "OpenViking: WebView process started (pid=\(process.processIdentifier))",
                name: "MemoryManagementVM"
            )
        } catch {
            DMLogger.error(
                "OpenViking: failed to launch WebView process: \(error.localizedDescription)",
                name: "MemoryManagementVM"
            )
            model.errorMessage = "启动 WebView 窗口失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    /// 从形如 `memory_3` / `user_0` 的 id 中提取 index。
    private func indexFromId(_ id: String) -> Int? {
        let parts = id.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return Int(parts[1])
    }
}
