import Foundation

/// 技能扫描服务 — 一比一还原 Flutter `SkillScannerService`，
/// 并扩展以支持扫描官方可选技能目录 `~/.hermes/hermes-agent/optional-skills/`。
///
/// 扫描两个目录：
/// - `~/.hermes/skills/` — 已安装的技能（区分内置 / 用户安装）
/// - `~/.hermes/hermes-agent/optional-skills/` — 官方随包发布的可选技能目录（默认未激活）
///
/// 已安装技能通过 `.bundled_manifest` 判断是否内置，通过 `.usage.json` 判断是否启用。
/// 可选技能目录仅返回结构化字段（id / category / path），
/// 展示用 name / description 由 `SkillCatalog` 解析。
nonisolated final class SkillScannerService {

    init() {}

    // MARK: - Paths

    /// `~/.hermes/hermes-agent/optional-skills/` — 官方可选技能目录。
    static func optionalSkillsDir() -> URL {
        let hermesHome = AppConstants.resolveHermesHome()
        return URL(fileURLWithPath: hermesHome)
            .appendingPathComponent("hermes-agent", isDirectory: true)
            .appendingPathComponent("optional-skills", isDirectory: true)
    }

    /// `~/.hermes/skills/` — 已安装技能根目录。
    static func installedSkillsDir() -> URL {
        let hermesHome = AppConstants.resolveHermesHome()
        return URL(fileURLWithPath: hermesHome)
            .appendingPathComponent("skills", isDirectory: true)
    }

    // MARK: - Public - Installed

    /// 扫描已安装技能 `~/.hermes/skills/` 并按分类返回 `RawSkillInfo` 列表。
    /// 结果形如：["apple": [RawSkillInfo, ...], "creative": [...], ...]
    func scanSkills() throws -> [String: [RawSkillInfo]] {
        let hermesHome = AppConstants.resolveHermesHome()
        let skillsDir = URL(fileURLWithPath: hermesHome)
            .appendingPathComponent("skills", isDirectory: true)

        let fm = FileManager.default
        guard fm.fileExists(atPath: skillsDir.path) else {
            return [:]
        }

        // 读取 bundled manifest（内置清单）
        let bundledIds = try readBundledManifest(skillsDir.path)
        // 读取 usage state（启用/禁用）
        let usageStates = try readUsageStates(skillsDir.path)

        var result: [String: [RawSkillInfo]] = [:]

        let entities = try fm.contentsOfDirectory(
            at: skillsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).sorted { $0.path < $1.path }

        for categoryURL in entities {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: categoryURL.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let categoryName = categoryURL.lastPathComponent
            // 跳过隐藏目录（双保险）
            if categoryName.hasPrefix(".") { continue }

            let subEntities = try fm.contentsOfDirectory(
                at: categoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).sorted { $0.path < $1.path }

            var skills: [RawSkillInfo] = []
            for sub in subEntities {
                var subIsDir: ObjCBool = false
                guard fm.fileExists(atPath: sub.path, isDirectory: &subIsDir),
                      subIsDir.boolValue else { continue }

                let skillId = sub.lastPathComponent
                if skillId.hasPrefix(".") { continue }

                // 必须包含 SKILL.md 才算有效技能
                let skillMd = sub.appendingPathComponent("SKILL.md")
                if !fm.fileExists(atPath: skillMd.path) { continue }

                let isBuiltIn = bundledIds.contains(skillId)
                let isEnabled = isEnabledFromStates(usageStates, skillId: skillId)

                skills.append(RawSkillInfo(
                    id: skillId,
                    category: categoryName,
                    path: "\(categoryName)/\(skillId)",
                    isBuiltIn: isBuiltIn,
                    isEnabled: isEnabled
                ))
            }

            if !skills.isEmpty {
                result[categoryName] = skills
            }
        }

        return result
    }

    // MARK: - Public - Optional Catalog

    /// 扫描官方可选技能目录 `~/.hermes/hermes-agent/optional-skills/`
    /// 并按分类返回所有未激活（但已发布）的技能。
    ///
    /// 与 `scanSkills()` 不同：
    /// - 此处不要求技能已安装到 `~/.hermes/skills/`
    /// - `isEnabled` 反映该可选技能当前是否已被用户安装启用
    /// - 分类目录名直接来自 `optional-skills/<category>/<skill>/`
    func scanOptionalSkills() throws -> [String: [OptionalSkillInfo]] {
        let optDir = Self.optionalSkillsDir()
        let fm = FileManager.default
        guard fm.fileExists(atPath: optDir.path) else {
            DMLogger.log(
                "scanOptionalSkills: optional-skills 目录不存在 \(optDir.path)",
                name: "SkillScannerService"
            )
            return [:]
        }

        // 已安装技能 id 集合 — 用于标记 isEnabled
        let installedIds = try collectInstalledIds()

        var result: [String: [OptionalSkillInfo]] = [:]

        let entities = try fm.contentsOfDirectory(
            at: optDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).sorted { $0.path < $1.path }

        for categoryURL in entities {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: categoryURL.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let categoryName = categoryURL.lastPathComponent
            if categoryName.hasPrefix(".") { continue }

            let subEntities = try fm.contentsOfDirectory(
                at: categoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).sorted { $0.path < $1.path }

            var skills: [OptionalSkillInfo] = []
            for sub in subEntities {
                var subIsDir: ObjCBool = false
                guard fm.fileExists(atPath: sub.path, isDirectory: &subIsDir),
                      subIsDir.boolValue else { continue }

                let skillId = sub.lastPathComponent
                if skillId.hasPrefix(".") { continue }

                // 必须包含 SKILL.md 才算有效技能
                let skillMd = sub.appendingPathComponent("SKILL.md")
                if !fm.fileExists(atPath: skillMd.path) { continue }

                skills.append(OptionalSkillInfo(
                    id: skillId,
                    category: categoryName,
                    path: "\(categoryName)/\(skillId)",
                    isInstalled: installedIds.contains(skillId)
                ))
            }

            if !skills.isEmpty {
                result[categoryName] = skills
            }
        }

        return result
    }

    /// 收集 `~/.hermes/skills/` 下所有技能 id 集合。
    /// 来自 SKILL.md 扫描结果（内置 + 用户安装）。
    private func collectInstalledIds() throws -> Set<String> {
        let installed = try scanSkills()
        var ids: Set<String> = []
        for (_, list) in installed {
            for raw in list { ids.insert(raw.id) }
        }
        return ids
    }

    // MARK: - Private

    /// 读取 `.bundled_manifest` 文件，返回内置技能 ID 集合。
    ///
    /// 文件格式（每行）：`<skill_id>:<relative_path>`
    /// 例如：`apple-notes:apple/apple-notes`
    private func readBundledManifest(_ skillsDir: String) throws -> Set<String> {
        let url = URL(fileURLWithPath: skillsDir)
            .appendingPathComponent(".bundled_manifest")
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [] }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            var ids = Set<String>()
            for line in content.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if let colon = trimmed.firstIndex(of: ":") {
                    let id = String(trimmed[..<colon])
                    if !id.isEmpty {
                        ids.insert(id)
                    }
                }
            }
            return ids
        } catch {
            DMLogger.error(
                "readBundledManifest failed: \(error.localizedDescription)",
                name: "SkillScannerService"
            )
            return []
        }
    }

    /// 读取 `.usage.json` 文件，返回 skillId → 是否激活。
    ///
    /// JSON 结构（简化）：
    /// ```
    /// { "<skillId>": { "state": "active" | "inactive", ... }, ... }
    /// ```
    private func readUsageStates(_ skillsDir: String) throws -> [String: Bool] {
        let url = URL(fileURLWithPath: skillsDir)
            .appendingPathComponent(".usage.json")
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return [:] }

        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            var states: [String: Bool] = [:]
            for (key, value) in json {
                if let dict = value as? [String: Any],
                   let state = dict["state"] as? String {
                    states[key] = (state == "active")
                }
            }
            return states
        } catch {
            DMLogger.error(
                "readUsageStates failed: \(error.localizedDescription)",
                name: "SkillScannerService"
            )
            return [:]
        }
    }

    /// 根据 usage 状态判断是否启用。文件中不存在时默认为启用 — 对齐 Flutter 行为。
    private func isEnabledFromStates(_ states: [String: Bool], skillId: String) -> Bool {
        if let v = states[skillId] { return v }
        return true
    }
}

// MARK: - Raw Skill Info

/// 磁盘上识别出的技能原始信息（仅结构化字段）— 对齐 Flutter `RawSkillInfo`。
struct RawSkillInfo: Equatable {
    let id: String
    /// 分类目录名，例如 "apple" / "creative"。
    let category: String
    /// 相对路径，例如 "apple/apple-notes"。
    let path: String
    let isBuiltIn: Bool
    let isEnabled: Bool
}

// MARK: - Optional Skill Info

/// 官方可选技能目录中识别出的技能原始信息。
///
/// 与 `RawSkillInfo` 不同：
/// - 没有 `isBuiltIn` 概念（这些技能一律不内置）
/// - `isInstalled` 表示该可选技能当前是否已被用户显式安装到 `~/.hermes/skills/`
struct OptionalSkillInfo: Equatable {
    let id: String
    let category: String
    let path: String
    let isInstalled: Bool
}
