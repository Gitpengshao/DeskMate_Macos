import Foundation
import Combine
import SwiftUI
import AppKit

/// 多智能体页面 ViewModel — 简化为左侧列表 + 右侧会话。
///
/// 职责：
/// 1. 加载并缓存 Hermes profile 列表。
/// 2. 管理左侧选中态。
/// 3. 为每个选中的智能体启动独立 Gateway，并按 profile 缓存
///    `AiChatViewModel` / `SessionListViewModel`，实现会话隔离与高性能切换。
/// 4. 提供新建 / 重命名 / 编辑描述 / 删除智能体能力。
@MainActor
final class AgentViewModel: ObservableObject {

    // MARK: - Shared instance
    //
    // 跨 tab 切换时保持同一个 ViewModel 实例，
    // 使得 `model.profiles` 与 `chatContainers` 的缓存能持久化。
    static let shared = AgentViewModel()

    // MARK: - Published State

    @Published private(set) var model: AgentPageModel = AgentPageModel(isLoading: true)

    /// 按 profile id 缓存的聊天容器；保证切换智能体时不丢失会话状态。
    @Published private(set) var chatContainers: [String: AgentChatContainer] = [:]

    /// 当前正在启动 Gateway / 准备聊天容器的 profile id（用于右侧展示启动中状态）。
    @Published private(set) var preparingProfileId: String? = nil

    // MARK: - Dependencies

    private let service: AgentService

    // MARK: - Init

    init(service: AgentService = .shared) {
        self.service = service
        // 仅当完全没有缓存时（首次启动）才主动加载；
        // 后续页面切换会通过 `silentRefresh()` 在后台静默拉取。
        if model.profiles.isEmpty {
            Task { [weak self] in
                await self?.loadProfiles(showLoading: true)
            }
        }
    }

    // MARK: - Loading

    /// 拉取所有 profile — 对齐 Flutter `_loadProfiles`。
    ///
    /// - Parameter showLoading: `true` 时显示全屏 loading（首次加载 / 用户主动刷新）；
    ///   `false` 时仅标记后台刷新状态，不打断页面（用于静默刷新）。
    func loadProfiles(showLoading: Bool = true) async {
        DMLogger.log(
            "[AgentVM] loadProfiles(showLoading=\(showLoading)) START",
            name: "AgentVM"
        )
        if showLoading {
            model = model.updating(isLoading: true, clearError: true)
        } else {
            // 后台静默刷新：如果已有缓存，不切到 loading 态。
            model = model.updating(
                isBackgroundRefreshing: true,
                clearError: true
            )
        }

        let profiles = await service.listProfiles()
        DMLogger.log(
            "[AgentVM] loadProfiles → \(profiles.count) profiles",
            name: "AgentVM"
        )

        // 选择默认选中的 profile：active > default > 第一个
        let selected: String = {
            if !model.selectedProfileId.isEmpty,
               profiles.contains(where: { $0.id == model.selectedProfileId }) {
                return model.selectedProfileId
            }
            if let active = profiles.first(where: { $0.isActive }) {
                return active.id
            }
            if let def = profiles.first(where: { $0.isDefault }) {
                return def.id
            }
            return profiles.first?.id ?? ""
        }()

        model = model.updating(
            profiles: profiles,
            selectedProfileId: selected,
            isLoading: false,
            isBackgroundRefreshing: false,
            clearError: true
        )
    }

    /// 刷新 — 对齐 Flutter `refresh()`。用户主动触发，会显示 loading 态。
    func refresh() async {
        await loadProfiles(showLoading: true)
    }

    /// 静默后台刷新 — 不显示 loading 态。
    /// - 首次打开 tab 且有缓存时立即展示上一次的列表，同时后台拉新数据。
    /// - 正在加载中（首次冷启动）时跳过，避免重复请求。
    /// - 已有后台刷新在进行时跳过。
    func silentRefresh() async {
        guard !model.isBackgroundRefreshing else { return }
        // 首屏冷启动时 `loadProfiles(showLoading: true)` 已经在跑，
        // 这里不要重复触发。
        if model.isLoading && !model.hasCache { return }
        // 没缓存时让用户看到 loading，而不是悄无声息地后台跑。
        if !model.hasCache {
            await loadProfiles(showLoading: true)
            return
        }
        await loadProfiles(showLoading: false)
    }

    // MARK: - Selection

    /// 选中某个 profile 并确保其 Gateway / 聊天容器就绪。
    func selectProfile(_ id: String) async {
        DMLogger.log("[AgentVM] selectProfile → \(id)", name: "AgentVM")
        model = model.updating(selectedProfileId: id)
        await prepareChat(for: id)
    }

    /// 获取指定 profile 的聊天容器（若尚未创建则返回 nil）。
    func chatContainer(for profileId: String) -> AgentChatContainer? {
        chatContainers[profileId]
    }

    /// 确保指定 profile 的 Gateway 正在运行，并创建/复用对应的聊天容器。
    func prepareChat(for profileId: String) async {
        DMLogger.log("[AgentVM] prepareChat → \(profileId)", name: "AgentVM")

        // 已存在容器时直接刷新状态，避免重复启动 Gateway / 重建 ViewModel。
        if let container = chatContainers[profileId] {
            container.sessionVM.loadSessions()
            container.chatVM.loadCurrentModel()
            container.chatVM.loadWorkingDirectory()
            return
        }

        preparingProfileId = profileId
        defer { preparingProfileId = nil }

        guard let (port, apiKey) = await HermesGatewayService.shared.ensureGatewayRunning(for: profileId) else {
            model = model.updating(
                errorMessage: "无法启动 \(profileId.isEmpty ? "默认" : profileId) 智能体的 Gateway"
            )
            return
        }

        let client = GatewayClient(host: "127.0.0.1", port: port, apiKey: apiKey)
        let chatVM = AiChatViewModel(gateway: client, profile: profileId)
        let sessionVM = SessionListViewModel(gateway: client, profile: profileId)
        let container = AgentChatContainer(profileId: profileId, chatVM: chatVM, sessionVM: sessionVM)
        chatContainers[profileId] = container

        container.sessionVM.loadSessions()
        container.chatVM.loadCurrentModel()
        container.chatVM.loadWorkingDirectory()
    }

    // MARK: - Search / Filter

    /// 设置搜索关键字。
    func setSearchQuery(_ query: String) {
        model = model.updating(searchQuery: query)
    }

    // MARK: - Mutations

    /// 创建 profile — 对齐 `hermes profile create`。
    func createProfile(
        name: String,
        mode: AgentCreateMode,
        description: String?,
        cloneFrom: String?
    ) async {
        DMLogger.log(
            "[AgentVM] createProfile \(name) mode=\(mode.rawValue)",
            name: "AgentVM"
        )
        model = model.updating(isLoading: true, clearError: true)

        let ok = await service.createProfile(
            name: name,
            mode: mode,
            description: description,
            cloneFrom: cloneFrom
        )

        if ok {
            model = model.updating(
                lastOperationLog: "✓ 已创建智能体: \(name)"
            )
            await loadProfiles()
            // 自动选中新创建的 profile 并启动其 Gateway
            if let new = model.profiles.first(where: { $0.id == name }) {
                await selectProfile(new.id)
            }
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "创建失败，请检查 hermes CLI 是否可用"
            model = model.updating(
                isLoading: false,
                errorMessage: "创建智能体失败: \(detail)"
            )
        }
    }

    /// 删除 profile — 对齐 `hermes profile delete`。
    func deleteProfile(_ name: String) async {
        DMLogger.log("[AgentVM] deleteProfile \(name)", name: "AgentVM")

        // 默认 profile 不可删除（官方文档）
        if name == "default" {
            model = model.updating(
                errorMessage: "默认智能体不可删除。如需完全卸载，请使用 hermes uninstall。"
            )
            return
        }

        model = model.updating(isLoading: true, clearError: true)

        // 先停止该 profile 的 Gateway 并释放缓存容器
        await HermesGatewayService.shared.stopGateway(for: name)
        chatContainers.removeValue(forKey: name)

        let ok = await service.deleteProfile(name: name, autoConfirm: true)

        if ok {
            model = model.updating(
                lastOperationLog: "✓ 已删除智能体: \(name)"
            )
            // 重新加载并清空选中
            await loadProfiles()
            if model.selectedProfileId == name {
                let fallbackId = model.profiles.first?.id ?? ""
                model = model.updating(selectedProfileId: fallbackId)
                if !fallbackId.isEmpty {
                    await selectProfile(fallbackId)
                }
            }
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "删除失败"
            model = model.updating(
                isLoading: false,
                errorMessage: "删除智能体失败: \(detail)"
            )
        }
    }

    /// 重命名 profile — 对齐 `hermes profile rename`。
    func renameProfile(_ oldName: String, to newName: String) async {
        DMLogger.log(
            "[AgentVM] renameProfile \(oldName) → \(newName)",
            name: "AgentVM"
        )
        model = model.updating(isLoading: true, clearError: true)

        // 重命名前停止旧 Gateway 并移除旧容器，避免端口/配置冲突
        await HermesGatewayService.shared.stopGateway(for: oldName)
        chatContainers.removeValue(forKey: oldName)

        let ok = await service.renameProfile(oldName: oldName, newName: newName)

        if ok {
            model = model.updating(
                lastOperationLog: "✓ 已重命名: \(oldName) → \(newName)"
            )
            if model.selectedProfileId == oldName {
                model = model.updating(selectedProfileId: newName)
            }
            await loadProfiles()
            // 自动选中新名称的 profile 并启动 Gateway
            await selectProfile(newName)
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "重命名失败"
            model = model.updating(
                isLoading: false,
                errorMessage: "重命名失败: \(detail)"
            )
        }
    }

    /// 设置/更新 description — 对齐 `hermes profile describe`。
    func describeProfile(_ name: String, description: String) async {
        DMLogger.log(
            "[AgentVM] describeProfile \(name) desc=\(description)",
            name: "AgentVM"
        )
        model = model.updating(isLoading: true, clearError: true)
        let ok = await service.describeProfile(name: name, description: description)

        if ok {
            model = model.updating(
                lastOperationLog: "✓ 已更新描述: \(name)"
            )
            await loadProfiles()
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "更新失败"
            model = model.updating(
                isLoading: false,
                errorMessage: "更新描述失败: \(detail)"
            )
        }
    }

    // MARK: - 错误清理

    /// 清除错误信息。
    func clearError() {
        model = model.updating(clearError: true)
    }
}
