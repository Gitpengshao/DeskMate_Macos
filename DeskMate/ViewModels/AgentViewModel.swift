import Foundation
import Combine
import AppKit
import SwiftUI

/// 多智能体页面 ViewModel — 一比一还原 Flutter `AgentViewModel`（Riverpod Notifier）。
///
/// MVVM 单一状态源：所有状态通过 `model: AgentPageModel` 发布；
/// View 通过 `@Published` 订阅更新。所有 CLI 写入均为异步，最终结果在
/// `@MainActor` 上 commit 到 `model`。
@MainActor
final class AgentViewModel: ObservableObject {

    // MARK: - Shared instance
    //
    // 跨 tab 切换时保持同一个 ViewModel 实例，
    // 使得 `model.profiles` 的缓存能持久化。
    // 与 `TBToast.Holder.shared` 模式一致。
    static let shared = AgentViewModel()

    // MARK: - Published State

    @Published private(set) var model: AgentPageModel = AgentPageModel(isLoading: true)

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

    /// 选中某个 profile — 对齐 Flutter `selectProfile`。
    func selectProfile(_ id: String) {
        DMLogger.log("[AgentVM] selectProfile → \(id)", name: "AgentVM")
        model = model.updating(selectedProfileId: id)
    }

    // MARK: - Search / Filter

    /// 设置搜索关键字。
    func setSearchQuery(_ query: String) {
        model = model.updating(searchQuery: query)
    }

    /// 切换「仅显示 distribution」。
    func toggleDistributionFilter(_ on: Bool) {
        model = model.updating(showOnlyDistributions: on)
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
                lastOperationLog: "✓ 已创建 profile: \(name) (\(mode.title))"
            )
            await loadProfiles()
            // 自动选中新创建的
            if let new = model.profiles.first(where: { $0.id == name }) {
                model = model.updating(selectedProfileId: new.id)
            }
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "创建失败，请检查 hermes CLI 是否可用"
            model = model.updating(
                isLoading: false,
                errorMessage: "创建 profile 失败: \(detail)"
            )
        }
    }

    /// 删除 profile — 对齐 `hermes profile delete`。
    func deleteProfile(_ name: String) async {
        DMLogger.log("[AgentVM] deleteProfile \(name)", name: "AgentVM")

        // 默认 profile 不可删除（官方文档）
        if name == "default" {
            model = model.updating(
                errorMessage: "默认 profile（~/.hermes）不可删除。如需完全卸载，请使用 hermes uninstall。"
            )
            return
        }

        model = model.updating(isLoading: true, clearError: true)
        let ok = await service.deleteProfile(name: name, autoConfirm: true)

        if ok {
            model = model.updating(
                lastOperationLog: "✓ 已删除 profile: \(name)"
            )
            // 重新加载并清空选中
            await loadProfiles()
            if model.selectedProfileId == name {
                model = model.updating(selectedProfileId: model.profiles.first?.id ?? "")
            }
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "删除失败"
            model = model.updating(
                isLoading: false,
                errorMessage: "删除 profile 失败: \(detail)"
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
        let ok = await service.renameProfile(oldName: oldName, newName: newName)

        if ok {
            model = model.updating(
                lastOperationLog: "✓ 已重命名: \(oldName) → \(newName)"
            )
            await loadProfiles()
            if model.selectedProfileId == oldName {
                model = model.updating(selectedProfileId: newName)
            }
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

    /// 粘性切换 — 对齐 `hermes profile use`。
    func useProfile(_ name: String) async {
        DMLogger.log("[AgentVM] useProfile \(name)", name: "AgentVM")
        model = model.updating(isLoading: true, clearError: true)
        let ok = await service.useProfile(name: name)

        if ok {
            // 本地更新 isActive 标记
            var updated = model.profiles.map { p -> AgentProfile in
                var copy = p
                copy.isActive = (p.id == name)
                return copy
            }
            _ = updated
            model = model.updating(
                profiles: model.profiles.map { p in
                    var copy = p
                    copy.isActive = (p.id == name)
                    return copy
                },
                lastOperationLog: "✓ 当前 profile 已切换为: \(name)"
            )
            await loadProfiles()
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "切换失败"
            model = model.updating(
                isLoading: false,
                errorMessage: "切换失败: \(detail)"
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
                lastOperationLog: "✓ 已更新 description: \(name)"
            )
            await loadProfiles()
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "更新失败"
            model = model.updating(
                isLoading: false,
                errorMessage: "更新 description 失败: \(detail)"
            )
        }
    }

    // MARK: - Distribution

    /// 安装 distribution — 对齐 `hermes profile install`。
    func installDistribution(
        source: String,
        name: String?,
        alias: Bool
    ) async {
        DMLogger.log(
            "[AgentVM] installDistribution source=\(source) name=\(name ?? "") alias=\(alias)",
            name: "AgentVM"
        )
        model = model.updating(isLoading: true, clearError: true)
        let ok = await service.installDistribution(
            source: source,
            name: name,
            alias: alias,
            autoConfirm: true
        )

        if ok {
            let aliasName = name ?? source
            model = model.updating(
                lastOperationLog: "✓ 已安装 distribution: \(aliasName)"
            )
            await loadProfiles()
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "安装失败"
            model = model.updating(
                isLoading: false,
                errorMessage: "安装 distribution 失败: \(detail)"
            )
        }
    }

    /// 更新 distribution — 对齐 `hermes profile update`。
    func updateDistribution(_ name: String) async {
        DMLogger.log(
            "[AgentVM] updateDistribution \(name)",
            name: "AgentVM"
        )
        model = model.updating(isLoading: true, clearError: true)
        let ok = await service.updateDistribution(name: name)

        if ok {
            model = model.updating(
                lastOperationLog: "✓ 已更新 distribution: \(name)"
            )
            await loadProfiles()
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "更新失败"
            model = model.updating(
                isLoading: false,
                errorMessage: "更新 distribution 失败: \(detail)"
            )
        }
    }

    // MARK: - Gateway per-profile

    /// 启动某 profile 的 gateway。
    func startGateway(for profileId: String) async {
        DMLogger.log(
            "[AgentVM] startGateway \(profileId)",
            name: "AgentVM"
        )
        let ok = await service.startGateway(profile: profileId)
        if ok {
            model = model.updating(
                lastOperationLog: "✓ Gateway 已启动: \(profileId)"
            )
            await loadProfiles()
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "启动失败"
            model = model.updating(errorMessage: "Gateway 启动失败: \(detail)")
        }
    }

    /// 停止某 profile 的 gateway。
    func stopGateway(for profileId: String) async {
        DMLogger.log(
            "[AgentVM] stopGateway \(profileId)",
            name: "AgentVM"
        )
        let ok = await service.stopGateway(profile: profileId)
        if ok {
            model = model.updating(
                lastOperationLog: "✓ Gateway 已停止: \(profileId)"
            )
            await loadProfiles()
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "停止失败"
            model = model.updating(errorMessage: "Gateway 停止失败: \(detail)")
        }
    }

    /// 安装为系统服务。
    func installGatewayService(for profileId: String) async {
        DMLogger.log(
            "[AgentVM] installGatewayService \(profileId)",
            name: "AgentVM"
        )
        let ok = await service.installGatewayService(profile: profileId)
        if ok {
            model = model.updating(
                lastOperationLog: "✓ Gateway 服务已安装: \(profileId)"
            )
        } else {
            let detail = service.lastError?.isEmpty == false
                ? service.lastError!
                : "安装服务失败"
            model = model.updating(errorMessage: "Gateway 服务安装失败: \(detail)")
        }
    }

    // MARK: - Export / Import

    /// 导出 profile — 对齐 `hermes profile export`。
    func exportProfile(_ name: String) async {
        DMLogger.log("[AgentVM] exportProfile \(name)", name: "AgentVM")
        model = model.updating(isLoading: true, clearError: true)
        if let tarball = await service.exportProfile(name: name) {
            // 在 Finder 中显示导出文件
            NSWorkspace.shared.activateFileViewerSelecting(
                [URL(fileURLWithPath: tarball)]
            )
            model = model.updating(
                isLoading: false,
                lastOperationLog: "✓ 已导出到: \(tarball)"
            )
        } else {
            model = model.updating(
                isLoading: false,
                errorMessage: "导出失败"
            )
        }
    }

    // MARK: - 文档跳转

    /// 打开官方 profiles 文档。
    func openProfilesDocs() {
        guard let url = URL(
            string: "https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/profiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开官方 distribution 文档。
    func openDistributionsDocs() {
        guard let url = URL(
            string: "https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/profile-distributions"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 错误清理

    /// 清除错误信息。
    func clearError() {
        model = model.updating(clearError: true)
    }
}
