import Foundation

/// 多智能体（profile）服务 — 封装 `hermes profile ...` CLI 调用。
///
/// 严格对齐官方文档
/// https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/profiles
/// https://hermes-agent.nousresearch.com/docs/zh-Hans/user-guide/profile-distributions
///
/// CLI 列表（来自官方文档）：
/// - `hermes profile list`                — 列出所有 profile
/// - `hermes profile show <name>`         — 显示某个 profile 的详细信息
/// - `hermes profile create <name> [...]` — 创建 profile
/// - `hermes profile delete <name> [--yes]`
/// - `hermes profile rename <old> <new>`
/// - `hermes profile export <name>`       — 导出 tar.gz
/// - `hermes profile import <tarball>`
/// - `hermes profile use <name>`          — 粘性当前 profile
/// - `hermes profile install <repo> [--alias] [--name]`
/// - `hermes profile update <name>`
/// - `hermes profile describe [name] [text]`
/// - `hermes -p <name> gateway start|stop|install`
///
/// 与 `TaskBoardService` 一样以 `nonisolated` 异步子进程方式执行；
/// ViewModel 在 `@MainActor` 上聚合结果。
nonisolated final class AgentService {

    // MARK: - Singleton

    static let shared = AgentService()

    /// 查询/读操作超时。
    private let queryTimeout: TimeInterval = 15
    /// 创建/更新/删除写操作超时。
    private let writeTimeout: TimeInterval = 60
    /// 克隆 / 安装 distribution 超时（可能涉及 git clone）。
    private let longTimeout: TimeInterval = 180

    /// 最近一次失败的原始 stderr（供 UI 展示）。
    nonisolated(unsafe) private(set) var lastError: String?

    private init() {}

    // MARK: - Public API

    // ---- List ----

    /// 列出所有 profile — 对齐 `hermes profile list [--json]`。
    ///
    /// 策略 1: `hermes profile list --json`
    /// 策略 2: 解析文本表格输出
    /// 策略 3: 文件系统兜底扫描 `~/.hermes/profiles/*/`
    func listProfiles() async -> [AgentProfile] {
        DMLogger.log("[AgentService] listProfiles START", name: "AgentService")

        // Strategy 1: --json
        if let arr = await runProfileCli(args: ["profile", "list", "--json"], timeout: queryTimeout) as? [Any] {
            let casted = arr.compactMap { $0 as? [String: Any] }
            if !casted.isEmpty {
                DMLogger.log(
                    "[AgentService] listProfiles Strategy1(JSON) → \(casted.count) profiles",
                    name: "AgentService"
                )
                return casted.map { AgentProfile.fromJson($0) }
            }
        }

        // Strategy 2: 表格输出
        if let table = await runProfileCli(args: ["profile", "list"], timeout: queryTimeout) as? String {
            let parsed = parseProfileTable(table)
            if !parsed.isEmpty {
                DMLogger.log(
                    "[AgentService] listProfiles Strategy2(TABLE) → \(parsed.count) profiles",
                    name: "AgentService"
                )
                return parsed.map { AgentProfile.fromJson($0) }
            }
        }

        // Strategy 3: 文件系统兜底
        DMLogger.log(
            "[AgentService] listProfiles Strategy3(FILESYSTEM) fallback",
            name: "AgentService"
        )
        return scanProfilesFromFilesystem()
    }

    // ---- Show ----

    /// 显示某个 profile 的详细信息 — 对齐 `hermes profile show <name>`。
    func showProfile(name: String) async -> AgentProfile? {
        DMLogger.log("[AgentService] showProfile \(name)", name: "AgentService")
        if let dict = await runProfileCli(
            args: ["show", name, "--json"],
            timeout: queryTimeout
        ) as? [String: Any] {
            return AgentProfile.fromJson(dict)
        }
        return nil
    }

    // ---- Create ----

    /// 创建 profile — 对齐 `hermes profile create <name> [...]`。
    ///
    /// 模式对应：
    /// - `blank`     → `hermes profile create <name> [--description "..."]`
    /// - `clone`     → `hermes profile create <name> --clone [--description "..."]`
    /// - `cloneAll`  → `hermes profile create <name> --clone-all [--description "..."]`
    /// - `cloneFrom` → `hermes profile create <name> --clone-from <source> [--description "..."]`
    @discardableResult
    func createProfile(
        name: String,
        mode: AgentCreateMode,
        description: String? = nil,
        cloneFrom: String? = nil
    ) async -> Bool {
        DMLogger.log(
            "[AgentService] createProfile name=\(name) mode=\(mode.rawValue) desc=\(description ?? "") cloneFrom=\(cloneFrom ?? "")",
            name: "AgentService"
        )

        guard Self.validateProfileName(name) else {
            DMLogger.error(
                "[AgentService] createProfile: name invalid: \(name)",
                name: "AgentService"
            )
            return false
        }

        var args: [String] = ["profile", "create", name]

        switch mode {
        case .blank:
            break
        case .clone:
            args.append("--clone")
        case .cloneAll:
            args.append("--clone-all")
        case .cloneFrom:
            guard let source = cloneFrom?.trimmingCharacters(in: .whitespaces),
                  !source.isEmpty else {
                DMLogger.error(
                    "[AgentService] createProfile: cloneFrom 模式需要指定源 profile",
                    name: "AgentService"
                )
                return false
            }
            args.append(contentsOf: ["--clone-from", source])
        }

        if let desc = description?.trimmingCharacters(in: .whitespaces),
           !desc.isEmpty {
            args.append(contentsOf: ["--description", desc])
        }

        let ok = await runProfileCliBool(args: args, timeout: writeTimeout)
        DMLogger.log(
            "[AgentService] createProfile \(name) → \(ok ? "OK" : "FAILED")",
            name: "AgentService"
        )
        return ok
    }

    // ---- Delete ----

    /// 删除 profile — 对齐 `hermes profile delete <name> [--yes]`。
    @discardableResult
    func deleteProfile(name: String, autoConfirm: Bool = false) async -> Bool {
        DMLogger.log("[AgentService] deleteProfile \(name)", name: "AgentService")
        var args: [String] = ["profile", "delete", name]
        if autoConfirm { args.append("--yes") }
        return await runProfileCliBool(args: args, timeout: writeTimeout)
    }

    // ---- Rename ----

    /// 重命名 profile — 对齐 `hermes profile rename <old> <new>`。
    @discardableResult
    func renameProfile(oldName: String, newName: String) async -> Bool {
        DMLogger.log(
            "[AgentService] renameProfile \(oldName) → \(newName)",
            name: "AgentService"
        )
        guard Self.validateProfileName(newName) else { return false }
        return await runProfileCliBool(
            args: ["profile", "rename", oldName, newName],
            timeout: writeTimeout
        )
    }

    // ---- Use (sticky) ----

    /// 粘性切换 — 对齐 `hermes profile use <name>`。
    @discardableResult
    func useProfile(name: String) async -> Bool {
        DMLogger.log("[AgentService] useProfile \(name)", name: "AgentService")
        return await runProfileCliBool(args: ["profile", "use", name], timeout: queryTimeout)
    }

    // ---- Describe ----

    /// 设置/读取 description — 对齐 `hermes profile describe [name] [text]`。
    @discardableResult
    func describeProfile(name: String, description: String) async -> Bool {
        DMLogger.log(
            "[AgentService] describeProfile \(name) desc=\(description)",
            name: "AgentService"
        )
        return await runProfileCliBool(
            args: ["profile", "describe", name, description],
            timeout: writeTimeout
        )
    }

    // ---- Export / Import ----

    /// 导出 profile — 对齐 `hermes profile export <name>`。
    ///
    /// 成功时返回 tarball 路径，失败时返回 `nil`。
    func exportProfile(name: String) async -> String? {
        DMLogger.log("[AgentService] exportProfile \(name)", name: "AgentService")
        let result = await runProfileCli(
            args: ["profile", "export", name],
            timeout: longTimeout
        )
        // `hermes profile export` 会输出 tarball 路径到 stdout。
        if let s = result as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        // 兜底：返回默认路径
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent("\(name).tar.gz")
    }

    /// 导入 profile — 对齐 `hermes profile import <tarball>`。
    @discardableResult
    func importProfile(tarballPath: String) async -> Bool {
        DMLogger.log(
            "[AgentService] importProfile \(tarballPath)",
            name: "AgentService"
        )
        return await runProfileCliBool(
            args: ["profile", "import", tarballPath],
            timeout: longTimeout
        )
    }

    // ---- Install distribution ----

    /// 从 git 仓库安装 distribution — 对齐 `hermes profile install <repo> [--alias] [--name]`。
    @discardableResult
    func installDistribution(
        source: String,
        name: String? = nil,
        alias: Bool = false,
        autoConfirm: Bool = false
    ) async -> Bool {
        DMLogger.log(
            "[AgentService] installDistribution source=\(source) name=\(name ?? "") alias=\(alias)",
            name: "AgentService"
        )
        var args: [String] = ["profile", "install", source]
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty {
            args.append(contentsOf: ["--name", n])
        }
        if alias { args.append("--alias") }
        if autoConfirm { args.append(contentsOf: ["-y", "--yes"]) }
        return await runProfileCliBool(args: args, timeout: longTimeout)
    }

    // ---- Update distribution ----

    /// 更新 distribution — 对齐 `hermes profile update <name>`。
    @discardableResult
    func updateDistribution(
        name: String,
        forceConfig: Bool = false
    ) async -> Bool {
        DMLogger.log(
            "[AgentService] updateDistribution \(name) forceConfig=\(forceConfig)",
            name: "AgentService"
        )
        var args: [String] = ["profile", "update", name]
        if forceConfig { args.append("--force-config") }
        return await runProfileCliBool(args: args, timeout: longTimeout)
    }

    // ---- Gateway per-profile ----

    /// 启动某 profile 的 gateway — 对齐 `hermes -p <name> gateway start`。
    /// 注意：`gateway start` 不支持 `--port` 参数，端口通过 `API_SERVER_PORT` 环境变量 / `.env` 控制。
    @discardableResult
    func startGateway(profile: String, port: Int = AppConstants.defaultGatewayPort) async -> Bool {
        DMLogger.log(
            "[AgentService] startGateway profile=\(profile) port=\(port)",
            name: "AgentService"
        )
        return await runProfileCliBool(
            args: ["-p", profile, "gateway", "start"],
            timeout: 30
        )
    }

    /// 停止某 profile 的 gateway — 对齐 `hermes -p <name> gateway stop`。
    @discardableResult
    func stopGateway(profile: String) async -> Bool {
        DMLogger.log(
            "[AgentService] stopGateway profile=\(profile)",
            name: "AgentService"
        )
        return await runProfileCliBool(
            args: ["-p", profile, "gateway", "stop"],
            timeout: 30
        )
    }

    /// 安装为系统服务（systemd / launchd）— 对齐 `<alias> gateway install`。
    @discardableResult
    func installGatewayService(profile: String) async -> Bool {
        DMLogger.log(
            "[AgentService] installGatewayService \(profile)",
            name: "AgentService"
        )
        return await runProfileCliBool(
            args: ["-p", profile, "gateway", "install"],
            timeout: 30
        )
    }

    // ---- Validation ----

    /// profile 名校验 — 1-64 字符，小写字母数字 + 连字符 / 下划线，首字符必须为字母数字。
    static func validateProfileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "-_"))
        guard let first = name.unicodeScalars.first,
              CharacterSet.lowercaseLetters.contains(first)
                || CharacterSet.decimalDigits.contains(first)
        else { return false }
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Process Helpers

    /// 执行 `hermes profile <args>` 子进程。
    private func runProfileCli(
        args: [String],
        timeout: TimeInterval
    ) async -> Any? {
        let result = await runHermesProfile(args: args, timeout: timeout)
        if !result.success {
            DMLogger.error(
                "[AgentService] CLI failed (\(result.exitCode)): \(result.stderr)",
                name: "AgentService"
            )
            lastError = result.stderr.isEmpty ? result.stdout : result.stderr
            return nil
        }
        lastError = nil

        // 优先 JSON 解析
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let data = trimmed.data(using: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data) {
                return json
            }
        }
        // 回退到原始字符串
        return result.stdout
    }

    /// 同上，但只关心成功 / 失败。
    private func runProfileCliBool(
        args: [String],
        timeout: TimeInterval
    ) async -> Bool {
        let result = await runHermesProfile(args: args, timeout: timeout)
        if !result.success {
            DMLogger.error(
                "[AgentService] CLI failed (\(result.exitCode)) stderr=\(result.stderr) stdout=\(result.stdout)",
                name: "AgentService"
            )
            lastError = result.stderr.isEmpty ? result.stdout : result.stderr
            return false
        }
        lastError = nil
        return true
    }

    /// 实际执行 `hermes profile <args>` 子进程。
    private func runHermesProfile(args: [String], timeout: TimeInterval) async -> ShellResult {
        let hermesHome = AppConstants.resolveHermesHome()
        let hermesBin = (hermesHome as NSString)
            .appendingPathComponent("hermes-agent/venv/bin/hermes")
        let fm = FileManager.default
        if !fm.isExecutableFile(atPath: hermesBin) {
            // 兜底: ~/.local/bin/hermes
            let fallback = "/Users/mac002/.local/bin/hermes"
            if fm.isExecutableFile(atPath: fallback) {
                return await runProcess(
                    executable: fallback,
                    args: args,
                    cwd: hermesHome,
                    timeout: timeout
                )
            }
            // 兜底: which hermes
            let whichResult = runShellSync("which hermes 2>/dev/null")
            let resolved = whichResult.trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolved.isEmpty, resolved.hasPrefix("/") {
                return await runProcess(
                    executable: resolved,
                    args: args,
                    cwd: hermesHome,
                    timeout: timeout
                )
            }
            DMLogger.error(
                "[AgentService] hermes binary not found at \(hermesBin)",
                name: "AgentService"
            )
            return ShellResult(
                success: false,
                exitCode: -1,
                stdout: "",
                stderr: "hermes binary not found at \(hermesBin)"
            )
        }
        return await runProcess(
            executable: hermesBin,
            args: args,
            cwd: hermesHome,
            timeout: timeout
        )
    }

    /// 子进程执行。
    private func runProcess(
        executable: String,
        args: [String],
        cwd: String,
        timeout: TimeInterval
    ) async -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryPath = cwd

        // 注入 .env
        let envPath = (cwd as NSString).appendingPathComponent(".env")
        var env = ProcessInfo.processInfo.environment
        env["HERMES_HOME"] = cwd
        if let envContent = try? String(contentsOfFile: envPath, encoding: .utf8) {
            for line in envContent.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let eqIdx = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
                var val = String(trimmed[trimmed.index(after: eqIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                val = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !val.isEmpty { env[key] = val }
            }
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ShellResult(
                success: false,
                exitCode: -1,
                stdout: "",
                stderr: "process.run() failed: \(error.localizedDescription)"
            )
        }

        // 带超时的等待
        let waitTask = Task { () -> Int32 in
            process.waitUntilExit()
            return process.terminationStatus
        }
        let timeoutTask = Task { () -> Int32 in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if process.isRunning {
                process.terminate()
            }
            return -1
        }

        let exitCode = await Task<Int32, Never> {
            // race: 第一个完成的任务胜出
            await withTaskGroup(of: Int32.self) { group in
                group.addTask { await waitTask.value }
                group.addTask { await timeoutTask.value }
                let first = await group.next() ?? -1
                group.cancelAll()
                return first
            }
        }.value

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        return ShellResult(
            success: exitCode == 0,
            exitCode: exitCode,
            stdout: stdout,
            stderr: stderr
        )
    }

    private func runShellSync(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    // MARK: - Fallback parsers

    /// 解析 `hermes profile list` 文本表格输出。
    ///
    /// 表格大致格式：
    /// ```
    /// Profile     Model                  Gateway    Alias    Distribution
    /// ─────────   ─────────────────────  ────────   ───────  ──────────────
    /// ◆default    claude-sonnet-4        stopped    —
    /// coder       gpt-5                  stopped    coder    —
    /// ```
    private func parseProfileTable(_ text: String) -> [[String: Any]] {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0) }

        // 找到 header 与分隔行
        var headerLine: String? = nil
        var dataStart = 0
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().contains("profile")
                && trimmed.lowercased().contains("model") {
                headerLine = trimmed
                dataStart = i + 1
                break
            }
        }
        guard let header = headerLine else { return [] }

        // 找表头各列的位置（多空格分隔）
        let columnNames = ["profile", "model", "gateway", "alias", "distribution"]
        var result: [[String: Any]] = []
        for i in dataStart..<lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // 跳过分隔线 ────────
            if trimmed.hasPrefix("─") || trimmed.hasPrefix("-") { continue }

            // 简单分列：按 ≥2 个空白字符切
            let parts = trimmed
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .filter { !$0.isEmpty }

            // 至少 2 列
            guard parts.count >= 2 else { continue }

            let idRaw = String(parts[0])
                .replacingOccurrences(of: "◆", with: "")
                .trimmingCharacters(in: .whitespaces)
            let id = idRaw.isEmpty ? "default" : idRaw

            let modelRaw = parts.count > 1 ? String(parts[1]) : ""
            let gatewayRaw = parts.count > 2 ? String(parts[2]) : ""
            let aliasRaw = parts.count > 3 ? String(parts[3]) : ""
            let distRaw = parts.count > 4 ? String(parts[4]) : ""

            let (provider, modelName) = CurrentModelInfo.parse(modelRaw)
            let isDefault = id == "default"
            let alias = (aliasRaw == "—") ? id : aliasRaw

            var dict: [String: Any] = [
                "id": id,
                "name": id,
                "display_name": id,
                "model": modelRaw,
                "provider": provider,
                "alias": alias,
                "is_default": isDefault,
                "is_active": isDefault,
            ]
            if !gatewayRaw.isEmpty && gatewayRaw != "—" {
                dict["gateway"] = gatewayRaw
            }
            if distRaw != "—" && !distRaw.isEmpty {
                // "research-bot@1.0.0"
                if let at = distRaw.firstIndex(of: "@") {
                    let name = String(distRaw[..<at])
                    let version = String(distRaw[distRaw.index(after: at)...])
                    dict["distribution"] = [
                        "name": name,
                        "version": version,
                    ]
                    dict["is_distribution"] = true
                }
            }
            // 兼容字段
            _ = modelName
            _ = header
            _ = columnNames
            result.append(dict)
        }
        return result
    }

    /// 文件系统兜底：扫描 `~/.hermes/profiles/<slug>/`。
    private func scanProfilesFromFilesystem() -> [AgentProfile] {
        let hermesHome = AppConstants.resolveHermesHome()
        let fm = FileManager.default
        var profiles: [AgentProfile] = []

        // 1. 默认 profile = ~/.hermes
        profiles.append(AgentProfile(
            id: "default",
            name: "default",
            description: "默认 profile（~/.hermes）",
            alias: "—",
            path: hermesHome,
            isDefault: true,
            isActive: true
        ))

        // 2. 扫描 ~/.hermes/profiles/*
        let profilesDir = (hermesHome as NSString)
            .appendingPathComponent("profiles")
        guard fm.fileExists(atPath: profilesDir) else { return profiles }

        guard let entities = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: profilesDir),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return profiles }

        for url in entities.sorted(by: { $0.path < $1.path }) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let slug = url.lastPathComponent
            if slug.hasPrefix(".") { continue }

            profiles.append(AgentProfile(
                id: slug,
                name: slug,
                description: "",
                alias: slug,
                path: url.path
            ))
        }
        return profiles
    }
}
