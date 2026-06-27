import Foundation

/// 候选 Python 解释器 — 对应一次探测结果。
struct PythonCandidate: Equatable, Identifiable, Hashable {
    /// 解释器绝对路径。
    let path: String
    /// 解释器版本，例如 `"Python 3.11.5"`。
    let version: String
    /// 解释器可执行文件所在目录（用于推断 site-packages 位置）。
    let binDir: String
    /// pip 版本，例如 `"23.2.1"`。
    let pipVersion: String
    /// 是否为系统自带的（Xcode / /usr/bin）。
    let isSystemPython: Bool

    var id: String { path }

    /// 展示用副标题。
    var displaySubtitle: String {
        "\(version) · pip \(pipVersion)"
    }
}

/// Python 解释器定位器 — 解决 Xcode 自带 Python（pip 21.2 太旧、找不到包）的问题。
///
/// 策略：
/// 1. 优先使用用户在 UI 中手动选择的路径（UserDefaults 持久化）；
/// 2. 否则扫描 macOS 常见安装位置（Homebrew / pyenv / miniconda / MacPorts / 系统）；
/// 3. 对每个候选执行 `<python> -m pip --version` 与 `<python> -V` 进行探测；
/// 4. 排除 `pip < 22` 的解释器（无法解析现代包元数据）；
/// 5. 第一个通过检测的解释器即默认。
nonisolated final class PythonLocator {

    /// UserDefaults key — 用户手动指定的 Python 路径。
    static let userOverrideKey = "DeskMate.OpenViking.PythonPath"

    /// UserDefaults key — 上次自动检测到的 Python 路径。
    static let lastAutoDetectedKey = "DeskMate.OpenViking.PythonPath.Auto"

    /// 默认 UserDefaults。
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// 解析当前应使用的 Python 解释器绝对路径。
    /// 优先级：用户手动选择 > 上次自动检测 > 现扫。
    func resolvePythonPath() async -> String? {
        if let manual = currentUserOverride(), FileManager.default.isExecutableFile(atPath: manual) {
            DMLogger.log(
                "PythonLocator: using user override \(manual)",
                name: "PythonLocator"
            )
            return manual
        }
        if let cached = defaults.string(forKey: Self.lastAutoDetectedKey),
           FileManager.default.isExecutableFile(atPath: cached) {
            // 仍然要快速验证 pip 仍可用
            if await probe(at: cached)?.pipIsHealthy == true {
                DMLogger.log(
                    "PythonLocator: using cached \(cached)",
                    name: "PythonLocator"
                )
                return cached
            }
        }
        if let best = await autoDetect() {
            defaults.set(best.path, forKey: Self.lastAutoDetectedKey)
            return best.path
        }
        return nil
    }

    /// 用户当前手动指定的 Python 路径（可能无效或不存在）。
    func currentUserOverride() -> String? {
        let trimmed = (defaults.string(forKey: Self.userOverrideKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 设置用户手动指定的 Python 路径。
    func setUserOverride(_ path: String?) {
        if let path, !path.isEmpty {
            defaults.set(path, forKey: Self.userOverrideKey)
        } else {
            defaults.removeObject(forKey: Self.userOverrideKey)
        }
    }

    /// 扫描所有候选并返回探测结果（用于 UI 列表展示）。
    func discoverCandidates() async -> [PythonCandidate] {
        var seen = Set<String>()
        var results: [PythonCandidate] = []
        for path in candidatePaths() where !seen.contains(path) {
            seen.insert(path)
            if let info = await probe(at: path) {
                results.append(info)
            }
        }
        return results
    }

    /// 自动挑选一个最合适的 Python 解释器。
    func autoDetect() async -> PythonCandidate? {
        let candidates = await discoverCandidates()
        // 优先 pip 版本 ≥ 22 且非系统 Python；再按路径排序
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.isSystemPython != rhs.isSystemPython {
                return !lhs.isSystemPython   // 系统的排后面
            }
            return pipVersionValue(lhs.pipVersion) > pipVersionValue(rhs.pipVersion)
        }
        return sorted.first
    }

    // MARK: - Candidate paths

    /// 常见的 macOS Python 路径（含 PATH 查找）。
    private func candidatePaths() -> [String] {
        var paths: [String] = []
        let home = NSHomeDirectory()

        // 1) PATH 中的 python3 / python
        paths.append(contentsOf: which("python3"))
        paths.append(contentsOf: which("python"))

        // 2) Homebrew（Apple Silicon + Intel）
        paths.append("/opt/homebrew/bin/python3")
        paths.append("/opt/homebrew/bin/python")
        paths.append("/usr/local/bin/python3")
        paths.append("/usr/local/bin/python")

        // 3) pyenv
        paths.append("\(home)/.pyenv/shims/python3")
        paths.append("\(home)/.pyenv/shims/python")

        // 4) Anaconda / Miniconda
        paths.append("\(home)/anaconda3/bin/python3")
        paths.append("\(home)/miniconda3/bin/python3")
        paths.append("\(home)/opt/anaconda3/bin/python3")
        paths.append("\(home)/.conda/envs/default/bin/python3")

        // 5) MacPorts
        paths.append("/opt/local/bin/python3")
        paths.append("/opt/local/bin/python")

        // 6) pipx / user-site
        paths.append("\(home)/.local/bin/python3")
        paths.append("\(home)/Library/Python/\(pythonMajorMinorGuess())/bin/python3")

        // 7) 系统（Xcode / /usr/bin）— 兜底
        paths.append("/usr/bin/python3")
        paths.append("/Applications/Xcode.app/Contents/Developer/usr/bin/python3")

        return paths
    }

    private func which(_ name: String) -> [String] {
        // 同步 PATH 扫描，避免再启进程
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let separator: Character = ":"
        var found: [String] = []
        for dir in pathEnv.split(separator: separator) {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                found.append(candidate)
            }
        }
        return found
    }

    private func pythonMajorMinorGuess() -> String {
        // 留作未来扩展；目前 Library/Python 仅 3.x
        return "3.11"
    }

    // MARK: - Probe

    /// 探测单个 Python 解释器。
    private func probe(at path: String) async -> PythonCandidate? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let versionResult = await runShortProcess(
            executable: path,
            args: ["-V"],
            timeout: 5
        )
        guard versionResult.exitCode == 0 else { return nil }
        let version = versionResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Python ", with: "Python ")
        if !version.lowercased().contains("python") { return nil }

        let pipResult = await runShortProcess(
            executable: path,
            args: ["-m", "pip", "--version"],
            timeout: 8
        )
        guard pipResult.exitCode == 0 else { return nil }
        // 输出形如: `pip 23.2.1 from /path/to/site-packages/pip (python 3.11)`
        let pipLine = pipResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let pipVersion = pipLine
            .split(separator: " ")
            .dropFirst()
            .first
            .map(String.init) ?? "?"

        let isSystem = path.hasPrefix("/usr/bin/") ||
                       path.hasPrefix("/System/") ||
                       path.contains("Xcode.app")

        let binDir = (path as NSString).deletingLastPathComponent
        return PythonCandidate(
            path: path,
            version: version,
            binDir: binDir,
            pipVersion: pipVersion,
            isSystemPython: isSystem
        )
    }

    /// 简短的进程执行（仅取 stdout/stderr/exitCode）。
    private func runShortProcess(
        executable: String,
        args: [String],
        timeout: TimeInterval
    ) async -> (exitCode: Int32, stdout: String, stderr: String) {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let outData = LockedBuffer()
            let errData = LockedBuffer()
            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if !d.isEmpty { outData.append(d) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if !d.isEmpty { errData.append(d) }
            }

            let resumed = LockedFlag()
            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if resumed.tryFlip() {
                    continuation.resume(returning: (
                        proc.terminationStatus,
                        outData.string() ?? "",
                        errData.string() ?? ""
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                if resumed.tryFlip() {
                    continuation.resume(returning: (-1, "", error.localizedDescription))
                }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    private func pipVersionValue(_ v: String) -> Int {
        // "23.2.1" → 230201
        let parts = v.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 10_000 + parts[1] * 100 + (parts.count >= 3 ? parts[2] : 0)
    }
}

// MARK: - Thread-safe helpers

private extension PythonCandidate {
    /// pip 是否健康（>= 22，能解析现代包元数据）。
    var pipIsHealthy: Bool {
        let parts = pipVersion.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else { return false }
        return major >= 22
    }
}

/// 线程安全的 Data 缓冲。
private final class LockedBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock(); data.append(chunk); lock.unlock()
    }

    func string() -> String? {
        lock.lock(); let copy = data; lock.unlock()
        return String(data: copy, encoding: .utf8)
    }
}

/// 线程安全的"只 resume 一次"标志。
private final class LockedFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func tryFlip() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
