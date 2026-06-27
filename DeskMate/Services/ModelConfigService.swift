import Foundation

/// 当前默认模型信息 — 对齐 Hermes `config.yaml` 中 `model` section。
///
/// Hermes 官方文档：
/// `~/.hermes/config.yaml` 顶层 `model:` 块下包含：
/// - `provider` (e.g. "openrouter")
/// - `default`  (e.g. "anthropic/claude-opus-4.7")
/// - `base_url`、`api_mode` 等可选字段
struct CurrentModelInfo: Equatable {
    /// 简称显示（去除 provider 前缀），例如 "claude-opus-4.7"。
    let displayName: String
    /// 完整 model id，例如 "anthropic/claude-opus-4.7"。
    let fullName: String
    /// Provider id，例如 "openrouter" / "anthropic" / "custom"。
    let provider: String

    /// 解析 "provider/model" 形式的字符串。
    /// - 若不带 "/" 则整段视为 modelName，provider 为空。
    static func parse(_ raw: String) -> (provider: String, modelName: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = trimmed.firstIndex(of: "/") {
            let prov = String(trimmed[..<slash]).trimmingCharacters(in: .whitespaces)
            let name = String(trimmed[trimmed.index(after: slash)...])
                .trimmingCharacters(in: .whitespaces)
            return (prov, name)
        }
        return ("", trimmed)
    }
}

/// 读取 `~/.hermes/config.yaml` 中默认模型配置 — 对齐官方文档
/// https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/configuring-models
///
/// 注意：UI 上显示的"当前默认模型"就是 `config.yaml` 中 `model.default` 的值。
/// 它控制 *新会话* 使用哪个模型；正在进行的会话保留首次启动时使用的模型
/// （如需热切换，需用 chat 内的 `/model <name>` 命令）。
final class ModelConfigService {

    private let hermesHome: String

    init(hermesHome: String = AppConstants.resolveHermesHome()) {
        self.hermesHome = hermesHome
    }

    /// 默认配置文件路径。
    var configPath: String {
        (hermesHome as NSString).appendingPathComponent("config.yaml")
    }

    /// 同步读取当前默认模型信息。
    /// - Returns: 解析成功时返回 `CurrentModelInfo`；缺失/解析失败时返回 `nil`。
    func readCurrentModel() -> CurrentModelInfo? {
        // 沙盒环境下 FileManager 可能无法直接访问 ~/.hermes/，
        // 因此与 OnboardingViewModel.checkConfigYamlForModel 一致，通过 shell 读取。
        let raw = runShell("cat '\(configPath)' 2>/dev/null")
        guard !raw.isEmpty else {
            DMLogger.log(
                "readCurrentModel: config.yaml 为空或不可读, path=\(configPath)",
                name: "ModelConfigService"
            )
            return nil
        }
        return parseModelSection(raw)
    }

    /// 解析 yaml 内容，提取 `model:` section 中的 `provider` 与 `default` 字段。
    ///
    /// 支持的最小子集：
    /// ```yaml
    /// model:
    ///   provider: openrouter
    ///   default: anthropic/claude-opus-4.7
    ///   base_url: ''
    /// ```
    /// 缩进统一识别为前导空格或 tab；遇到新的顶层 key 退出。
    private func parseModelSection(_ content: String) -> CurrentModelInfo? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        var inModelSection = false
        var defaultRaw: String?
        var providerRaw: String?

        for raw in lines {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")

            if !inModelSection {
                // 顶层 `model:` key（必须无缩进，且以冒号结尾）
                if !isIndented && (trimmed == "model:" || trimmed.hasPrefix("model:")) {
                    inModelSection = true
                }
                continue
            }

            // 已在 model section：遇到新的顶层 key 退出
            if !isIndented {
                break
            }

            // 解析 `key: value`
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
                // 去掉行内注释（# 之前的内容，但需在引号外）
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            // 行内注释剥离（极简：不处理嵌套引号，Hermes 配置通常无此情况）
            if let hash = value.firstIndex(of: "#") {
                value = String(value[..<hash])
                    .trimmingCharacters(in: .whitespaces)
            }

            switch key {
            case "default":
                if !value.isEmpty { defaultRaw = value }
            case "provider":
                if !value.isEmpty { providerRaw = value }
            default:
                continue
            }
        }

        guard let defaultValue = defaultRaw, !defaultValue.isEmpty else {
            DMLogger.log(
                "parseModelSection: 未找到 model.default",
                name: "ModelConfigService"
            )
            return nil
        }

        // provider 字段可能为空，此时从 default 值本身解析 "provider/model" 前缀
        let provider: String
        let fullName: String
        if let p = providerRaw, !p.isEmpty {
            provider = p
            fullName = defaultValue
        } else {
            let parsed = CurrentModelInfo.parse(defaultValue)
            provider = parsed.provider
            fullName = parsed.modelName.isEmpty ? defaultValue : parsed.modelName
        }

        // 进一步解析 default：若包含 "/"，则短名取最后一段
        let displayName: String
        if fullName.contains("/") {
            displayName = String(fullName.split(separator: "/").last ?? Substring(fullName))
        } else {
            displayName = fullName
        }

        DMLogger.log(
            "parseModelSection: provider=\(provider), default=\(defaultValue), " +
            "displayName=\(displayName)",
            name: "ModelConfigService"
        )

        return CurrentModelInfo(
            displayName: displayName,
            fullName: defaultValue,
            provider: provider
        )
    }

    // MARK: - Shell

    /// 通过 /bin/bash 执行命令并返回 stdout。
    /// 沙盒环境下用于访问真实 ~/.hermes/。
    private func runShell(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            DMLogger.error(
                "runShell 启动失败: \(error.localizedDescription), cmd=\(command)",
                name: "ModelConfigService"
            )
            return ""
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
