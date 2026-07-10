import Foundation

/// 封装系统 `git` 命令调用，为文件树状态提供 Git 状态数据。
///
/// 说明：SwiftGitX 目前未暴露 status API，因此本服务直接调用 git CLI。
enum GitCommandService {

    /// 获取工作区所有文件的 git 状态。
    ///
    /// 返回数组元素：`(statusCode, path)`，statusCode 为前两位状态字符，如 "M "、" M"、"??"。
    static func status(
        workingDirectory: String
    ) async -> [(status: String, path: String)] {
        let result = await runGit(
            args: ["status", "--porcelain"],
            workingDirectory: workingDirectory
        )
        guard result.exitCode == 0 else { return [] }

        return result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> (status: String, path: String)? in
                let text = String(line)
                guard text.count >= 4 else { return nil }
                let status = String(text.prefix(2))
                let rest = String(text.dropFirst(3))
                // 重命名格式："R  old\tnew"
                if status.hasPrefix("R") || status.hasPrefix("C") {
                    let parts = rest.split(separator: "\t", omittingEmptySubsequences: false)
                    let displayPath = parts.count >= 2 ? String(parts[1]) : rest
                    return (status: status, path: displayPath)
                }
                // 普通路径可能带引号
                return (status: status, path: rest.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
            }
    }

    // MARK: - Private

    private static func runGit(
        args: [String],
        workingDirectory: String
    ) async -> StreamingProcessRunner.Result {
        do {
            return try await StreamingProcessRunner.run(
                executable: "/usr/bin/git",
                args: args,
                timeout: 30,
                logName: "GitCommandService"
            )
        } catch {
            DMLogger.error("GitCommandService: git 命令异常 \(args): \(error.localizedDescription)", name: "GitCommandService")
            return StreamingProcessRunner.Result(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
    }
}
