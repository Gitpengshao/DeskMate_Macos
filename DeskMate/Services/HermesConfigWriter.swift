import Foundation

/// `~/.hermes/config.yaml` 中 `model:` 块的当前主模型信息。
///
/// 对齐 Flutter `CurrentModelConfig`。
struct CurrentModelConfig: Equatable {
    let provider: String?
    let model: String?
    let baseUrl: String?

    static let empty = CurrentModelConfig(provider: nil, model: nil, baseUrl: nil)
}

/// `config.yaml` `auxiliary:` 块中单个任务条目的原始数据。
///
/// 对齐 Flutter `AuxiliaryConfigRaw`。
struct AuxiliaryConfigRaw: Equatable {
    let provider: String?
    let model: String?
    let baseUrl: String?
    let apiKey: String?

    static let empty = AuxiliaryConfigRaw(provider: nil, model: nil, baseUrl: nil, apiKey: nil)

    var isAuto: Bool {
        provider == nil || provider == "auto" || (model ?? "").isEmpty
    }
}

/// Hermes 配置文件（`config.yaml` & `.env`）的读写器。
///
/// 对齐 Flutter `HermesService` 中以下方法的 macOS 实现：
///   - `readModelConfig()` / `writeModelConfig()` / `clearModelConfig()`
///   - `readAuxiliaryConfig()` / `writeAuxiliaryConfig()` / `resetAllAuxiliary()`
///   - `getDefaultApiKey(provider)` / `writeApiKeyToEnv(provider, apiKey)`
///
/// 所有方法都是同步的（Swift 调用栈上等待），调用方应在后台线程使用。
final class HermesConfigWriter {

    static let shared = HermesConfigWriter()

    /// 当前 writer 对应的 profile；`nil` 表示默认 profile（`~/.hermes`）。
    let profile: String?
    private let hermesHome: String

    /// 创建对应 profile 的 config writer。
    ///
    /// - `profile` 为 `nil` / `default` / 空字符串时使用默认 home。
    /// - 显式传入 `hermesHome` 时优先使用（覆盖 profile 计算）。
    init(profile: String? = nil, hermesHome: String? = nil) {
        self.profile = profile?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hermesHome = hermesHome, !hermesHome.isEmpty {
            self.hermesHome = hermesHome
        } else {
            self.hermesHome = AppConstants.resolveHermesHome(for: self.profile)
        }
        DMLogger.log("HermesConfigWriter init: profile=\(self.profile ?? "default") hermesHome=\(self.hermesHome)", name: "HermesConfigWriter")
    }

    /// 工厂方法：获取对应 profile 的 writer。
    static func forProfile(_ profile: String?) -> HermesConfigWriter {
        guard let profile = profile?.trimmingCharacters(in: .whitespacesAndNewlines),
              !profile.isEmpty, profile != "default" else {
            return shared
        }
        return HermesConfigWriter(profile: profile)
    }

    // MARK: - Paths

    private var configPath: String {
        (hermesHome as NSString).appendingPathComponent(AppConstants.hermesConfigFile)
    }
    private var envPath: String {
        (hermesHome as NSString).appendingPathComponent(AppConstants.hermesEnvFile)
    }

    // MARK: - readModelConfig

    /// 读取 `config.yaml` 中 `model:` 块的当前主模型。
    func readModelConfig() -> CurrentModelConfig {
        let content = readFileOrEmpty(path: configPath)
        guard !content.isEmpty else { return .empty }
        return parseModelBlock(content: content)
    }

    /// 解析 yaml 内容中的 model 块。
    private func parseModelBlock(content: String) -> CurrentModelConfig {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var inModel = false
        var provider: String?
        var model: String?
        var baseUrl: String?

        for raw in lines {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")

            if !inModel {
                if !isIndented && (trimmed == "model:" || trimmed.hasPrefix("model:")) {
                    inModel = true
                }
                continue
            }
            // 遇到下一个顶层 key，退出
            if !isIndented { break }

            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if let hash = value.firstIndex(of: "#") {
                value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            switch key {
            case "provider":
                if !value.isEmpty { provider = value }
            case "default":
                if !value.isEmpty { model = value }
            case "base_url":
                if !value.isEmpty { baseUrl = value }
            default:
                continue
            }
        }

        DMLogger.log(
            "parseModelBlock: provider=\(provider ?? "nil") model=\(model ?? "nil") baseUrl=\(baseUrl ?? "nil")",
            name: "HermesConfigWriter"
        )
        return CurrentModelConfig(provider: provider, model: model, baseUrl: baseUrl)
    }

    // MARK: - writeModelConfig

    /// 写入主模型到 `config.yaml`。
    ///
    /// - Parameters:
    ///   - provider: 供应商 id（builtin 名称、custom 名称或 "auto"）。
    ///   - model: 模型 id。
    ///   - baseUrl: 自定义 baseUrl（内置供应商无需传入，会自动 lookup）。
    func writeModelConfig(provider: String, model: String, baseUrl: String?) {
        DMLogger.log(
            "[writeModelConfig] provider=\(provider) model=\(model) baseUrl=\(baseUrl ?? "nil")",
            name: "HermesConfigWriter"
        )

        var content = readFileOrEmpty(path: configPath)
        // 先移除整个 model 块
        content = removeBlock(content: content, parentKey: "model")

        // 硅基流动等非 Hermes 一等供应商需要以 `provider: custom` + base_url 的方式写入。
        let actualProvider = hermesProviderName(for: provider)
        let actualBaseUrl = resolveBaseUrl(
            provider: provider,
            baseUrl: baseUrl,
            actualProvider: actualProvider
        )
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        var buffer = ""
        if !trimmed.isEmpty {
            buffer = trimmed + "\n"
        }
        buffer += "model:\n"
        buffer += "  provider: \(actualProvider)\n"
        buffer += "  default: \(model)\n"
        if let url = actualBaseUrl, !url.isEmpty {
            buffer += "  base_url: \(url)\n"
        }

        ensureDirectoryExists(path: hermesHome)
        do {
            try buffer.write(toFile: configPath, atomically: true, encoding: .utf8)
            DMLogger.log("[writeModelConfig] wrote config.yaml", name: "HermesConfigWriter")
        } catch {
            DMLogger.error(
                "[writeModelConfig] write failed: \(error.localizedDescription)",
                name: "HermesConfigWriter"
            )
        }
    }

    /// 清除 model 块。
    func clearModelConfig() {
        let content = readFileOrEmpty(path: configPath)
        if content.isEmpty { return }
        let new = removeBlock(content: content, parentKey: "model")
        do {
            try new.write(toFile: configPath, atomically: true, encoding: .utf8)
            DMLogger.log("[clearModelConfig] cleared model block", name: "HermesConfigWriter")
        } catch {
            DMLogger.error(
                "[clearModelConfig] failed: \(error.localizedDescription)",
                name: "HermesConfigWriter"
            )
        }
    }

    /// 计算 provider 的最终 baseUrl。
    ///
    /// - Parameters:
    ///   - provider: DeskMate 预设的供应商 id（如 "siliconflow"）。
    ///   - baseUrl: UI 传入的自定义 baseUrl（可能为 nil）。
    ///   - actualProvider: 即将写入 config.yaml 的 Hermes provider 名。
    ///     若已被映射成 `custom`（见 `hermesProviderName(for:)`），则必须用
    ///     DeskMate 预设的 base_url，而不是用户可能传过来的 nil。
    private func resolveBaseUrl(
        provider: String,
        baseUrl: String?,
        actualProvider: String? = nil
    ) -> String? {
        let actual = actualProvider ?? hermesProviderName(for: provider)
        if actual == "auto" { return nil }
        if actual == "custom" {
            // 对于被映射为 `custom` 的预设，UI 通常不会传 baseUrl（因为它就是从预设来的），
            // 但用户在 "自定义" 模式下也可能会传。这里优先用 DeskMate 预设的 URL。
            return kProviderBaseUrls[provider] ?? baseUrl
        }
        return kProviderBaseUrls[provider] ?? baseUrl
    }

    /// 把 DeskMate 预设的供应商 id 翻译为 Hermes 实际认识的 provider 名。
    ///
    /// 例如 `siliconflow` → `custom`（因为 Hermes 不存在 siliconflow 这个一等供应商）。
    /// 直接传 `custom` / `auto` / Hermes 一等供应商时不变。
    private func hermesProviderName(for provider: String) -> String {
        if kProvidersAsCustomAlias.contains(provider) { return "custom" }
        return provider
    }

    // MARK: - readAuxiliaryConfig

    /// 读取辅助任务配置，key 为任务 yaml key（如 "vision"）。
    func readAuxiliaryConfig() -> [String: AuxiliaryConfigRaw] {
        let content = readFileOrEmpty(path: configPath)
        guard !content.isEmpty else { return [:] }
        return parseAuxiliaryBlock(content: content)
    }

    /// 解析 `auxiliary:` 块。
    private func parseAuxiliaryBlock(content: String) -> [String: AuxiliaryConfigRaw] {
        var result: [String: AuxiliaryConfigRaw] = [:]
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        var auxStart: Int? = nil
        for i in 0..<lines.count {
            if String(lines[i]).trimmingCharacters(in: .whitespaces) == "auxiliary:" {
                auxStart = i
                break
            }
        }
        guard let start = auxStart else { return result }

        // block 结束
        var blockEnd = lines.count
        for j in (start + 1)..<lines.count {
            let l = String(lines[j])
            if l.isEmpty { continue }
            if !l.hasPrefix(" ") && !l.hasPrefix("\t") {
                blockEnd = j
                break
            }
        }

        var currentTask: String? = nil
        for i in (start + 1)..<blockEnd {
            let line = String(lines[i])
            // 2 空格缩进：task key
            if let taskMatch = line.range(of: "^  ([A-Za-z0-9_]+):\\s*$", options: .regularExpression) {
                let keyPart = String(line[taskMatch])
                let name = keyPart
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentTask = name
                result[name] = .empty
                continue
            }
            // 4 空格缩进：task property
            if let task = currentTask {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("provider:") {
                    let v = trimmed.replacingOccurrences(of: "provider:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    result[task] = AuxiliaryConfigRaw(
                        provider: v.isEmpty ? nil : v,
                        model: result[task]?.model,
                        baseUrl: result[task]?.baseUrl,
                        apiKey: result[task]?.apiKey
                    )
                } else if trimmed.hasPrefix("model:") {
                    let v = trimmed.replacingOccurrences(of: "model:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    result[task] = AuxiliaryConfigRaw(
                        provider: result[task]?.provider,
                        model: v.isEmpty ? nil : v,
                        baseUrl: result[task]?.baseUrl,
                        apiKey: result[task]?.apiKey
                    )
                } else if trimmed.hasPrefix("api_key:") {
                    let v = trimmed.replacingOccurrences(of: "api_key:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    result[task] = AuxiliaryConfigRaw(
                        provider: result[task]?.provider,
                        model: result[task]?.model,
                        baseUrl: result[task]?.baseUrl,
                        apiKey: v.isEmpty ? nil : v
                    )
                } else if trimmed.hasPrefix("base_url:") {
                    let v = trimmed.replacingOccurrences(of: "base_url:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    result[task] = AuxiliaryConfigRaw(
                        provider: result[task]?.provider,
                        model: result[task]?.model,
                        baseUrl: v.isEmpty ? nil : v,
                        apiKey: result[task]?.apiKey
                    )
                }
            }
        }
        DMLogger.log(
            "parseAuxiliaryBlock: keys=\(result.keys.sorted())",
            name: "HermesConfigWriter"
        )
        return result
    }

    // MARK: - writeAuxiliaryConfig

    /// 写入单个辅助任务配置。
    ///
    /// - Parameters:
    ///   - taskKey: 任务 yaml key（如 "vision"）。
    ///   - provider: 供应商 id 或 "auto"。
    ///   - model: 模型 id（provider == "auto" 时可为空）。
    ///   - baseUrl: 自定义 baseUrl。
    ///   - apiKey: API Key（写入 config.yaml 的 api_key 字段）。
    func writeAuxiliaryConfig(
        taskKey: String,
        provider: String,
        model: String,
        baseUrl: String? = nil,
        apiKey: String? = nil
    ) {
        DMLogger.log(
            "[writeAuxiliaryConfig] task=\(taskKey) provider=\(provider) model=\(model)",
            name: "HermesConfigWriter"
        )

        var content = readFileOrEmpty(path: configPath)
        let existing = parseAuxiliaryBlock(content: content)

        // 辅助任务同样需要把硅基流动等非 Hermes 一等供应商映射为 `custom`，
        // 避免 Hermes 报 "Unknown provider"。
        let actualProvider = hermesProviderName(for: provider)
        let actualBaseUrl = resolveBaseUrl(
            provider: provider,
            baseUrl: baseUrl,
            actualProvider: actualProvider
        )

        var newDict = existing
        newDict[taskKey] = AuxiliaryConfigRaw(
            provider: actualProvider == "auto" ? "auto" : actualProvider,
            model: model,
            baseUrl: actualBaseUrl,
            apiKey: apiKey
        )

        // 构造新的 auxiliary 块
        var auxBuffer = "auxiliary:\n"
        let keys = newDict.keys.sorted()
        for key in keys {
            guard let cfg = newDict[key] else { continue }
            auxBuffer += "  \(key):\n"
            auxBuffer += "    provider: \(cfg.provider ?? "")\n"
            auxBuffer += "    model: \(cfg.model ?? "")\n"
            if let u = cfg.baseUrl, !u.isEmpty {
                auxBuffer += "    base_url: \(u)\n"
            }
            if let k = cfg.apiKey, !k.isEmpty {
                auxBuffer += "    api_key: \(k)\n"
            }
        }

        // 替换或追加
        if let start = findBlockStart(content: content, key: "auxiliary") {
            let end = findBlockEnd(content: content, start: start)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var newLines = lines
            newLines.replaceSubrange(start..<end, with: auxBuffer.split(separator: "\n").map(String.init))
            content = newLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        } else {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                content = "\n" + auxBuffer
            } else {
                content = trimmed + "\n\n" + auxBuffer
            }
        }

        ensureDirectoryExists(path: hermesHome)
        do {
            try content.write(toFile: configPath, atomically: true, encoding: .utf8)
            DMLogger.log("[writeAuxiliaryConfig] wrote auxiliary block", name: "HermesConfigWriter")
        } catch {
            DMLogger.error(
                "[writeAuxiliaryConfig] write failed: \(error.localizedDescription)",
                name: "HermesConfigWriter"
            )
        }
    }

    /// 清除所有辅助任务配置（恢复 auto）。
    func resetAllAuxiliary() {
        let content = readFileOrEmpty(path: configPath)
        guard !content.isEmpty else { return }
        let new = removeBlock(content: content, parentKey: "auxiliary")
        do {
            try new.write(toFile: configPath, atomically: true, encoding: .utf8)
            DMLogger.log("[resetAllAuxiliary] cleared auxiliary block", name: "HermesConfigWriter")
        } catch {
            DMLogger.error(
                "[resetAllAuxiliary] failed: \(error.localizedDescription)",
                name: "HermesConfigWriter"
            )
        }
    }

    // MARK: - readReasoningEffort / writeReasoningEffort

    /// 读取 `config.yaml` 中 `agent.reasoning_effort` 字段。
    ///
    /// 官方文档：
    /// `agent.reasoning_effort: "medium"  # none | low | minimal | medium | high | xhigh`
    ///
    /// - 当文件不存在、未配置 `agent:` 块或字段缺失时返回 `.medium`（与官方默认值一致）。
    /// - 解析失败时同样回退到 `.medium`，不抛错。
    func readReasoningEffort() -> ReasoningEffort {
        let content = readFileOrEmpty(path: configPath)
        guard !content.isEmpty else {
            DMLogger.log(
                "readReasoningEffort: config missing, defaulting to .medium",
                name: "HermesConfigWriter"
            )
            return .medium
        }
        let raw = parseAgentField(content: content, key: "reasoning_effort")
        let effort = ReasoningEffort.parse(raw)
        DMLogger.log(
            "readReasoningEffort: raw=\(raw ?? "nil") -> \(effort.rawValue)",
            name: "HermesConfigWriter"
        )
        return effort
    }

    /// 写入 `agent.reasoning_effort` 到 `config.yaml`。
    ///
    /// 行为：
    /// - 若 `agent:` 块已存在，则仅替换/插入 `reasoning_effort:` 行，保留其它键。
    /// - 若 `agent:` 块不存在，则在文件末尾追加最小块（含 `reasoning_effort`）。
    /// - 写入失败仅记日志，不抛错。
    func writeReasoningEffort(_ effort: ReasoningEffort) {
        DMLogger.log(
            "[writeReasoningEffort] effort=\(effort.rawValue)",
            name: "HermesConfigWriter"
        )
        var content = readFileOrEmpty(path: configPath)
        content = upsertAgentField(
            content: content,
            key: "reasoning_effort",
            value: effort.rawValue
        )
        ensureDirectoryExists(path: hermesHome)
        do {
            try content.write(toFile: configPath, atomically: true, encoding: .utf8)
            DMLogger.log(
                "[writeReasoningEffort] wrote \(effort.rawValue) to config.yaml",
                name: "HermesConfigWriter"
            )
        } catch {
            DMLogger.error(
                "[writeReasoningEffort] failed: \(error.localizedDescription)",
                name: "HermesConfigWriter"
            )
        }
    }

    // MARK: - getDefaultApiKey / writeApiKeyToEnv

    /// 读取 `.env` 中指定 provider 的默认 API Key。
    ///
    /// provider "openai" -> "OPENAI_API_KEY"。
    /// 对 `kProvidersAsCustomAlias`（如 "siliconflow"）仍使用 DeskMate 预设 id
    /// 对应的 env 变量（"SILICONFLOW_API_KEY"），与 Flutter 实现保持一致。
    /// Hermes 对 `provider: custom` + base_url 的解析会通过主机名推导
    /// `<VENDOR>_API_KEY`，因此该变量正是实际生效的 key。
    func getDefaultApiKey(provider: String) -> String? {
        let content = readFileOrEmpty(path: envPath)
        guard !content.isEmpty else { return nil }
        let envVar = envVarName(for: provider)
        return parseEnvValue(content: content, key: envVar)
    }

    /// 写入或更新 `.env` 中 provider 的 API Key。
    /// - 当 `apiKey` 为 nil 或空时，移除对应键。
    /// - 对 `kProvidersAsCustomAlias` 中的预设，使用 DeskMate 预设 id 对应的
    ///   env 变量（如 "SILICONFLOW_API_KEY"），而不是 `CUSTOM_API_KEY`。
    func writeApiKeyToEnv(provider: String, apiKey: String?) {
        let envVar = envVarName(for: provider)
        DMLogger.log(
            "[writeApiKeyToEnv] provider=\(provider) envVarName=\(envVar) " +
            "apiKey=\(apiKey != nil ? "有值(长度\(apiKey!.count))" : "null")",
            name: "HermesConfigWriter"
        )

        ensureDirectoryExists(path: hermesHome)
        let oldContent = readFileOrEmpty(path: envPath)
        var lines = oldContent.isEmpty ? [] : oldContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var foundIndex: Int? = nil
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(envVar)=") {
                foundIndex = i
                break
            }
        }

        if let idx = foundIndex {
            if let key = apiKey, !key.isEmpty {
                lines[idx] = "\(envVar)=\(key)"
                DMLogger.log("[writeApiKeyToEnv] updated line at \(idx)", name: "HermesConfigWriter")
            } else {
                lines.remove(at: idx)
                DMLogger.log("[writeApiKeyToEnv] removed line at \(idx)", name: "HermesConfigWriter")
            }
        } else {
            if let key = apiKey, !key.isEmpty {
                lines.append("\(envVar)=\(key)")
                DMLogger.log("[writeApiKeyToEnv] appended new line", name: "HermesConfigWriter")
            } else {
                DMLogger.log("[writeApiKeyToEnv] nothing to write", name: "HermesConfigWriter")
            }
        }

        let newContent = lines.joined(separator: "\n")
            + (lines.isEmpty ? "" : "\n")
        do {
            try newContent.write(toFile: envPath, atomically: true, encoding: .utf8)
            DMLogger.log(
                "[writeApiKeyToEnv] wrote \(envContentLength(newContent)) chars to env",
                name: "HermesConfigWriter"
            )
        } catch {
            DMLogger.error(
                "[writeApiKeyToEnv] failed: \(error.localizedDescription)",
                name: "HermesConfigWriter"
            )
        }
    }

    private func envContentLength(_ s: String) -> Int { s.count }

    /// 读取整个 .env 字典（供调试或后续扩展使用）。
    func readAllEnvVars() -> [String: String] {
        let content = readFileOrEmpty(path: envPath)
        guard !content.isEmpty else { return [:] }
        var out: [String: String] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            var val = String(trimmed[trimmed.index(after: eq)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if val.isEmpty { continue }
            if key == "API_SERVER_KEY" { val = "***" }
            out[key] = val
        }
        return out
    }

    private func envVarName(for provider: String) -> String {
        // 与 Flutter `HermesService.writeApiKeyToEnv` 保持一致：env 变量名直接使用
        // DeskMate 预设 provider id 推导，例如 "siliconflow" -> "SILICONFLOW_API_KEY"。
        // Hermes 对 `provider: custom` + base_url 的解析会通过主机名自动匹配该变量。
        let normalized = provider.replacingOccurrences(of: "-", with: "_").uppercased()
        return "\(normalized)_API_KEY"
    }

    private func parseEnvValue(content: String, key: String) -> String? {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let lineKey = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            if lineKey == key {
                var val = String(trimmed[trimmed.index(after: eq)...])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if val.isEmpty { return nil }
                return val
            }
        }
        return nil
    }

    // MARK: - Generic env write / remove

    /// 写入/更新多个 env 变量。
    ///
    /// - value 为 nil 或空字符串时移除对应键（与 `writeApiKeyToEnv` 行为一致）。
    /// - 调用方负责先调用 `removeEnvVarsWithPrefix` 清理旧字段，避免残留。
    func writeEnvVars(_ vars: [(key: String, value: String?)]) {
        ensureDirectoryExists(path: hermesHome)
        let oldContent = readFileOrEmpty(path: envPath)
        var lines = oldContent.isEmpty ? [] : oldContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (key, value) in vars {
            var foundIndex: Int? = nil
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(key)=") {
                    foundIndex = i
                    break
                }
            }
            if let idx = foundIndex {
                if let v = value, !v.isEmpty {
                    lines[idx] = "\(key)=\(v)"
                } else {
                    lines.remove(at: idx)
                }
            } else {
                if let v = value, !v.isEmpty {
                    lines.append("\(key)=\(v)")
                }
            }
        }

        let newContent = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        do {
            try newContent.write(toFile: envPath, atomically: true, encoding: .utf8)
            DMLogger.log("[writeEnvVars] wrote \(vars.count) keys to env", name: "HermesConfigWriter")
        } catch {
            DMLogger.error("[writeEnvVars] failed: \(error.localizedDescription)", name: "HermesConfigWriter")
        }
    }

    /// 移除所有以指定前缀开头的 env 变量（如 `FEISHU_` / `WEIXIN_`）。
    func removeEnvVarsWithPrefix(_ prefix: String) {
        let oldContent = readFileOrEmpty(path: envPath)
        guard !oldContent.isEmpty else { return }
        var lines = oldContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("\(prefix)")
        }
        let newContent = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        do {
            try newContent.write(toFile: envPath, atomically: true, encoding: .utf8)
            DMLogger.log("[removeEnvVarsWithPrefix] removed \(prefix)*", name: "HermesConfigWriter")
        } catch {
            DMLogger.error("[removeEnvVarsWithPrefix] failed: \(error.localizedDescription)", name: "HermesConfigWriter")
        }
    }

    // MARK: - YAML helpers

    /// 读取文件内容（不存在返回空串）。
    private func readFileOrEmpty(path: String) -> String {
        guard FileManager.default.fileExists(atPath: path) else { return "" }
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            DMLogger.error(
                "readFileOrEmpty failed: \(error.localizedDescription), path=\(path)",
                name: "HermesConfigWriter"
            )
            return ""
        }
    }

    private func ensureDirectoryExists(path: String) {
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// 查找顶层 key 在文件中的行号（`key:` 且无缩进）。
    private func findBlockStart(content: String, key: String) -> Int? {
        let pattern = "^\(key):\\s*$"
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, raw) in lines.enumerated() {
            let line = String(raw)
            if line.range(of: pattern, options: .regularExpression) != nil {
                return i
            }
        }
        return nil
    }

    /// 块的结束行（下一个顶层 key 行号）。
    private func findBlockEnd(content: String, start: Int) -> Int {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        if start + 1 >= lines.count { return lines.count }
        for j in (start + 1)..<lines.count {
            let l = String(lines[j])
            if l.isEmpty { continue }
            if !l.hasPrefix(" ") && !l.hasPrefix("\t") {
                return j
            }
        }
        return lines.count
    }

    /// 移除整个 YAML 块（顶层 key 及其所有缩进子行）。
    private func removeBlock(content: String, parentKey: String) -> String {
        let pattern = "^\(parentKey):\\s*$"
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var parentLine = -1
        for (i, l) in lines.enumerated() {
            if l.range(of: pattern, options: .regularExpression) != nil {
                parentLine = i
                break
            }
        }
        if parentLine == -1 { return content }
        var blockEnd = lines.count
        for j in (parentLine + 1)..<lines.count {
            let l = lines[j]
            if l.isEmpty { continue }
            if !l.hasPrefix(" ") && !l.hasPrefix("\t") {
                blockEnd = j
                break
            }
        }
        var newLines = lines
        newLines.removeSubrange(parentLine..<blockEnd)
        return newLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: - terminal cwd

    /// 读取 `config.yaml` 中 `terminal.cwd` 字段。
    ///
    /// 官方文档：`terminal.cwd` 指定 `terminal` 后端执行命令时的工作目录。
    /// - 未配置时返回 nil，表示使用 Hermes 默认行为。
    func readTerminalCwd() -> String? {
        let content = readFileOrEmpty(path: configPath)
        guard !content.isEmpty else { return nil }
        return parseBlockField(content: content, block: "terminal", key: "cwd")
    }

    /// 写入或清除 `terminal.cwd` 到 `config.yaml`。
    ///
    /// - 传入有效路径时，写入/更新 `terminal.cwd`。
    /// - 传入 nil 或空字符串时，移除 `terminal.cwd` 字段（若 terminal 块变空则移除整个块）。
    func writeTerminalCwd(_ path: String?) {
        DMLogger.log("[writeTerminalCwd] path=\(path ?? "nil")", name: "HermesConfigWriter")
        var content = readFileOrEmpty(path: configPath)
        if let path = path, !path.isEmpty {
            content = upsertBlockField(content: content, block: "terminal", key: "cwd", value: path)
        } else {
            content = removeBlockField(content: content, block: "terminal", key: "cwd")
        }
        ensureDirectoryExists(path: hermesHome)
        do {
            try content.write(toFile: configPath, atomically: true, encoding: .utf8)
            DMLogger.log("[writeTerminalCwd] wrote cwd=\(path ?? "nil")", name: "HermesConfigWriter")
        } catch {
            DMLogger.error("[writeTerminalCwd] failed: \(error.localizedDescription)", name: "HermesConfigWriter")
        }
    }

    // MARK: - agent block helpers

    /// 解析 `agent:` 块下指定 2-空格缩进字段的原始字符串值。
    private func parseAgentField(content: String, key: String) -> String? {
        parseBlockField(content: content, block: "agent", key: key)
    }

    /// 在 `agent:` 块下插入或替换 2-空格缩进字段。
    private func upsertAgentField(content: String, key: String, value: String) -> String {
        upsertBlockField(content: content, block: "agent", key: key, value: value)
    }

    // MARK: - generic block helpers

    /// 解析任意顶层块下指定 2-空格缩进字段的原始字符串值。
    ///
    /// 字段值会去除首尾空白与可选的引号；未找到返回 nil。
    private func parseBlockField(content: String, block: String, key: String) -> String? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var inBlock = false
        for raw in lines {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")
            if !inBlock {
                if !isIndented && trimmed == "\(block):" { inBlock = true }
                continue
            }
            // 离开块
            if !isIndented { return nil }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let fieldKey = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            if fieldKey != key { continue }
            var value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if let hash = value.firstIndex(of: "#") {
                value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// 在任意顶层块下插入或替换 2-空格缩进字段。
    ///
    /// - 块不存在时：追加最小块（仅含该字段）。
    /// - 字段已存在：替换该行，保留其它行。
    /// - 字段不存在：在块末尾（块结束前）追加。
    private func upsertBlockField(content: String, block: String, key: String, value: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blockStart: Int? = nil
        for (i, l) in lines.enumerated() {
            if l.range(of: "^\(block):\\s*$", options: .regularExpression) != nil {
                blockStart = i
                break
            }
        }

        guard let start = blockStart else {
            // 不存在块 — 追加最小块
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let newBlock = "\(block):\n  \(key): \(value)\n"
            if trimmed.isEmpty { return newBlock }
            return trimmed + "\n\n" + newBlock
        }

        // 找到块结束
        var blockEnd = lines.count
        for j in (start + 1)..<lines.count {
            let l = lines[j]
            if l.isEmpty { continue }
            if !l.hasPrefix(" ") && !l.hasPrefix("\t") {
                blockEnd = j
                break
            }
        }

        // 查找已有 key 行
        let keyPattern = "^  \(NSRegularExpression.escapedPattern(for: key)):\\s*"
        var keyLineIdx: Int? = nil
        for i in (start + 1)..<blockEnd {
            let l = lines[i]
            if l.range(of: keyPattern, options: .regularExpression) != nil {
                keyLineIdx = i
                break
            }
        }

        var newLines = lines
        if let idx = keyLineIdx {
            newLines[idx] = "  \(key): \(value)"
        } else {
            // 插到块的最后一个非空行之后
            var insertAt = blockEnd
            for k in (start + 1..<blockEnd).reversed() {
                if !lines[k].trimmingCharacters(in: .whitespaces).isEmpty {
                    insertAt = k + 1
                    break
                }
            }
            newLines.insert("  \(key): \(value)", at: insertAt)
        }
        return newLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// 从任意顶层块中移除指定字段；若块变空则移除整个块。
    private func removeBlockField(content: String, block: String, key: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blockStart: Int? = nil
        for (i, l) in lines.enumerated() {
            if l.range(of: "^\(block):\\s*$", options: .regularExpression) != nil {
                blockStart = i
                break
            }
        }
        guard let start = blockStart else { return content }

        var blockEnd = lines.count
        for j in (start + 1)..<lines.count {
            let l = lines[j]
            if l.isEmpty { continue }
            if !l.hasPrefix(" ") && !l.hasPrefix("\t") {
                blockEnd = j
                break
            }
        }

        let keyPattern = "^  \(NSRegularExpression.escapedPattern(for: key)):\\s*"
        var keyLineIdx: Int? = nil
        for i in (start + 1)..<blockEnd {
            let l = lines[i]
            if l.range(of: keyPattern, options: .regularExpression) != nil {
                keyLineIdx = i
                break
            }
        }

        guard let idx = keyLineIdx else { return content }

        var newLines = lines
        newLines.remove(at: idx)

        // 重新计算块结束位置（基于移除 key 行后的新数组）
        var newBlockEnd = newLines.count
        for j in (start + 1)..<newLines.count {
            let l = newLines[j]
            if l.isEmpty { continue }
            if !l.hasPrefix(" ") && !l.hasPrefix("\t") {
                newBlockEnd = j
                break
            }
        }

        // 若块内只剩空行/注释，则移除整个块
        var remainingNonEmpty = false
        for i in (start + 1)..<newBlockEnd {
            let trimmed = newLines[i].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                remainingNonEmpty = true
                break
            }
        }
        if !remainingNonEmpty {
            newLines.removeSubrange(start..<newBlockEnd)
        }

        return newLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
