import Foundation
import SwiftUI
import Combine

/// 模型配置页 ViewModel — 对齐 Flutter `ModelConfigViewModel`（Riverpod Notifier）。
///
/// MVVM：管理 `model: ModelConfigModel` 单一状态源；
/// View 通过 `@Published` 订阅更新。所有文件写入与 Gateway 重启均为异步。
@MainActor
final class ModelConfigViewModel: ObservableObject {

    @Published var model: ModelConfigModel

    /// 加载状态（与 Flutter 的 AsyncValue 状态对应）。
    @Published var isLoading: Bool = false
    /// 最近一次错误信息（与 Flutter 的 AsyncValue.error 对应）。
    @Published var loadError: String? = nil

    /// 是否正在保存（用于对话框按钮的禁用态）。
    @Published var isSaving: Bool = false

    private let configWriter: HermesConfigWriter
    private let gateway: HermesGatewayService

    /// 通知 Gateway 状态变化（用于首页刷新连接状态）。
    /// 与 Flutter 中 `ref.invalidate(homeViewModelProvider)` 对应。
    let gatewayStateChanged = PassthroughSubject<Void, Never>()

    init(
        configWriter: HermesConfigWriter = .shared,
        gateway: HermesGatewayService
    ) {
        self.configWriter = configWriter
        self.gateway = gateway
        self.model = ModelConfigModel()
    }

    /// 默认初始化器，使用全局 Gateway 单例。
    @MainActor
    convenience init() {
        self.init(
            configWriter: .shared,
            gateway: HermesGatewayService.shared
        )
    }

    // MARK: - Build (load from Hermes)

    /// 加载当前主模型与辅助任务配置。
    /// 对齐 Flutter `build()` 与 `_loadFromHermes()`。
    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        DMLogger.log("[ModelConfigVM] load 开始...", name: "ModelConfigVM")

        let current = configWriter.readModelConfig()
        let rawAux = configWriter.readAuxiliaryConfig()
        let provider = current.provider ?? ""
        let modelId = current.model ?? ""
        let resolvedBaseUrl = current.baseUrl ?? ""

        // `kProvidersAsCustomAlias`（如 "siliconflow"）在 Hermes 端实际写入为
        // `provider: custom` + `base_url`，需要在加载时通过 base_url 反查
        // DeskMate 预设，以便 UI 仍然展示 "硅基流动" 等用户熟悉的标签。
        let matchedPreset: String? = {
            guard provider == "custom" else { return nil }
            guard !resolvedBaseUrl.isEmpty else { return nil }
            return kProviderPresetByBaseUrl(resolvedBaseUrl)
        }()
        let effectiveProvider = matchedPreset ?? provider

        // 对匹配到预设的，实际 API key 在 `CUSTOM_API_KEY` 里（config.yaml 里写的是 custom）。
        let apiKey = configWriter.getDefaultApiKey(provider: effectiveProvider)
        let isBuiltin = kProviderBaseUrls[effectiveProvider] != nil

        var auxDict: [AuxiliaryTaskType: AuxiliaryModelConfig] = [:]
        for task in AuxiliaryTaskType.allCases {
            let raw = rawAux[task.yamlKey]
            if let raw = raw, !raw.isAuto {
                // 辅助任务同样做 base_url -> DeskMate 预设反查
                let auxMatched: String? = {
                    guard raw.provider == "custom" else { return nil }
                    guard let url = raw.baseUrl, !url.isEmpty else { return nil }
                    return kProviderPresetByBaseUrl(url)
                }()
                auxDict[task] = AuxiliaryModelConfig(
                    task: task,
                    provider: auxMatched ?? raw.provider,
                    model: raw.model,
                    baseUrl: raw.baseUrl,
                    apiKey: raw.apiKey
                )
            } else {
                auxDict[task] = AuxiliaryModelConfig(task: task)
            }
        }

        self.model = ModelConfigModel(
            providerKey: effectiveProvider,
            providerLabel: kProviderDisplayNames[effectiveProvider] ?? effectiveProvider,
            modelId: modelId,
            apiKey: apiKey,
            baseUrl: current.baseUrl ?? kProviderBaseUrls[effectiveProvider],
            providerType: isBuiltin ? .builtin : .custom,
            avatarLetter: kProviderIconEmojis[effectiveProvider] ?? "M",
            auxiliary: auxDict
        )

        DMLogger.log(
            "[ModelConfigVM] load 完成: provider=\(effectiveProvider) model=\(modelId) " +
            "aux overrides=\(model.hasAuxiliaryOverrides)",
            name: "ModelConfigVM"
        )
    }

    /// 重新拉取配置（写入后调用）。
    /// 对齐 Flutter `refresh()`。
    func refresh() async {
        DMLogger.log("[ModelConfigVM] refresh", name: "ModelConfigVM")
        await load()
    }

    // MARK: - Update Current Model

    /// 更新主模型配置 — 对齐 Flutter `updateCurrentModel`。
    ///
    /// 流程：
    /// 1. 写入 API key 到 .env
    /// 2. 写入 model 块到 config.yaml
    /// 3. 写入 desktop pet agent 配置（首次）
    /// 4. 重启 Gateway
    /// 5. 刷新 model 状态 + 通知首页
    func updateCurrentModel(
        provider: String,
        model: String,
        baseUrl: String?,
        apiKey: String?
    ) async {
        DMLogger.log(
            "[ModelConfigVM] updateCurrentModel provider=\(provider) model=\(model)",
            name: "ModelConfigVM"
        )
        isSaving = true
        defer { isSaving = false }

        if let key = apiKey, !key.isEmpty {
            configWriter.writeApiKeyToEnv(provider: provider, apiKey: key)
        }
        configWriter.writeModelConfig(provider: provider, model: model, baseUrl: baseUrl)
        writeAgentConfigIfNeeded()
        await restartGateway()
        await load()
    }

    /// 写入 desktop pet agent 块（首次时），对齐 Flutter `writeAgentConfig`。
    /// 若 config.yaml 中已存在 agent: 块则跳过。
    private func writeAgentConfigIfNeeded() {
        let content: String
        do {
            content = try String(
                contentsOfFile: AppConstants.hermesPath(AppConstants.hermesConfigFile),
                encoding: .utf8
            )
        } catch {
            DMLogger.error(
                "writeAgentConfigIfNeeded: read config.yaml failed: \(error.localizedDescription)",
                name: "ModelConfigVM"
            )
            return
        }

        if content.range(of: "^agent:\\s*$", options: .regularExpression) != nil {
            DMLogger.log(
                "writeAgentConfigIfNeeded: agent block exists, skip",
                name: "ModelConfigVM"
            )
            return
        }

        let personalities = kDesktopPetPersonalities
        var block = "agent:\n"
        block += "  max_turns: 60\n"
        block += "  gateway_timeout: 1800\n"
        block += "  restart_drain_timeout: 180\n"
        block += "  api_max_retries: 3\n"
        block += "  service_tier: ''\n"
        block += "  tool_use_enforcement: auto\n"
        block += "  task_completion_guidance: true\n"
        block += "  environment_probe: true\n"
        block += "  environment_hint: ''\n"
        block += "  coding_context: auto\n"
        block += "  gateway_timeout_warning: 900\n"
        block += "  clarify_timeout: 600\n"
        block += "  gateway_notify_interval: 180\n"
        block += "  gateway_auto_continue_freshness: 3600\n"
        block += "  image_input_mode: auto\n"
        block += "  disabled_toolsets: []\n"
        block += "  verbose: false\n"
        block += "  reasoning_effort: medium\n"
        block += "  personalities:\n"
        let entries = Array(personalities)
        for (_, e) in entries.enumerated() {
            let escaped = e.value.replacingOccurrences(of: "'", with: "''")
            block += "    \(e.key): '\(escaped)'\n"
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let newContent = (trimmed.isEmpty ? "" : trimmed + "\n\n") + block
        do {
            try newContent.write(
                toFile: AppConstants.hermesPath(AppConstants.hermesConfigFile),
                atomically: true,
                encoding: .utf8
            )
            DMLogger.log(
                "writeAgentConfigIfNeeded: wrote agent block with \(entries.count) personalities",
                name: "ModelConfigVM"
            )
        } catch {
            DMLogger.error(
                "writeAgentConfigIfNeeded: write failed: \(error.localizedDescription)",
                name: "ModelConfigVM"
            )
        }
    }

    // MARK: - Auxiliary Model

    /// 设置辅助任务模型覆盖 — 对齐 Flutter `setAuxiliaryModel`。
    func setAuxiliaryModel(
        task: AuxiliaryTaskType,
        provider: String,
        model: String,
        baseUrl: String? = nil,
        apiKey: String? = nil
    ) async {
        DMLogger.log(
            "[ModelConfigVM] setAuxiliaryModel task=\(task.yamlKey) " +
            "provider=\(provider) model=\(model)",
            name: "ModelConfigVM"
        )
        isSaving = true
        defer { isSaving = false }

        if let key = apiKey, !key.isEmpty {
            configWriter.writeApiKeyToEnv(provider: provider, apiKey: key)
        }
        configWriter.writeAuxiliaryConfig(
            taskKey: task.yamlKey,
            provider: provider,
            model: model,
            baseUrl: baseUrl,
            apiKey: apiKey
        )
        await restartGateway()
        await load()
    }

    /// 重置单个辅助任务为 auto — 对齐 Flutter `resetAuxiliaryTask`。
    func resetAuxiliaryTask(_ task: AuxiliaryTaskType) async {
        DMLogger.log(
            "[ModelConfigVM] resetAuxiliaryTask task=\(task.yamlKey)",
            name: "ModelConfigVM"
        )
        isSaving = true
        defer { isSaving = false }

        configWriter.writeAuxiliaryConfig(
            taskKey: task.yamlKey,
            provider: "auto",
            model: ""
        )
        await restartGateway()
        await load()
    }

    /// 重置所有辅助任务为 auto — 对齐 Flutter `resetAllAuxiliary`。
    func resetAllAuxiliary() async {
        DMLogger.log("[ModelConfigVM] resetAllAuxiliary", name: "ModelConfigVM")
        isSaving = true
        defer { isSaving = false }

        configWriter.resetAllAuxiliary()
        await restartGateway()
        await load()
    }

    // MARK: - Gateway

    /// 重启 Gateway 让配置生效，并刷新全局相关状态。
    /// 对齐 Flutter `restartGateway`。
    ///
    /// 使用 `stopAllGateways()` 而非 `stopGateway(for:)`，确保清理崩溃/未正常退出的
    /// 残留 Hermes Gateway 进程，避免 8642 端口被占用导致新实例启动失败。
    func restartGateway() async {
        DMLogger.log("[ModelConfigVM] restartGateway 开始", name: "ModelConfigVM")
        await gateway.stopAllGateways()
        DMLogger.log("[ModelConfigVM] Gateway 已停止并清理残留进程", name: "ModelConfigVM")
        let started = await gateway.startGateway()
        DMLogger.log("[ModelConfigVM] Gateway 已启动 success=\(started)", name: "ModelConfigVM")

        // 刷新全局状态：网关连接徽标、AI 对话当前模型显示等。
        await refreshAppStateAfterModelChange()

        gatewayStateChanged.send()
        NotificationCenter.default.post(name: .modelConfigDidChange, object: nil)
    }

    /// Gateway 重启成功后刷新整个 App 中与模型相关的状态。
    /// 重点刷新 AI 对话数据：当前模型徽标、当前会话消息。
    private func refreshAppStateAfterModelChange() async {
        DMLogger.log("[ModelConfigVM] 开始刷新全局模型相关状态", name: "ModelConfigVM")

        // 1. 刷新顶部 Gateway 连接状态徽标
        await GatewayConnectionManager.shared.refresh()

        // 2. 刷新 AI 对话页当前模型显示
        AiChatViewModel.shared.loadCurrentModel()

        // 3. 如果当前有会话，重新加载该会话以同步最新后端数据
        if let sessionId = AiChatViewModel.shared.model.sessionId, !sessionId.isEmpty {
            DMLogger.log(
                "[ModelConfigVM] 重新加载当前会话 sessionId=\(sessionId)",
                name: "ModelConfigVM"
            )
            AiChatViewModel.shared.loadSession(sessionId)
        }

        DMLogger.log("[ModelConfigVM] 全局模型相关状态刷新完成", name: "ModelConfigVM")
    }

    // MARK: - Discover Models

    /// 探测某个 provider 可用的模型 — 对齐 Flutter `discoverModels`。
    /// 当前实现：从 `kDefaultModelForProvider` 拿到默认；未来可扩展为请求 Gateway。
    func discoverModels(provider: String) -> [String] {
        if let m = kDefaultModelForProvider[provider] {
            return [m]
        }
        return []
    }

    /// 读取某个 provider 的默认 API Key — 对齐 Flutter `getDefaultApiKey`。
    func defaultApiKey(for provider: String) -> String? {
        configWriter.getDefaultApiKey(provider: provider)
    }
}
