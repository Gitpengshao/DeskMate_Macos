import Foundation

/// 封装系统 `git` 命令调用，为 diff 审查提供数据与操作。
///
/// 说明：SwiftGitX 目前未暴露 Diff/Patch/Hunk API，因此本服务直接调用 git CLI。
enum GitCommandService {

    /// 检测指定目录是否为 Git 仓库。
    static func isGitRepository(at workingDirectory: String) async -> Bool {
        let result = await runGit(
            args: ["rev-parse", "--git-dir"],
            workingDirectory: workingDirectory
        )
        return result.exitCode == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 获取单个文件工作区与 HEAD 的 unified diff。
    ///
    /// - Parameter contextLines: hunk 上下文行数，默认 3。
    static func diff(
        workingDirectory: String,
        path: String,
        contextLines: Int = 3
    ) async -> String {
        let result = await runGit(
            args: ["diff", "-U\(contextLines)", "--", path],
            workingDirectory: workingDirectory
        )
        return result.stdout
    }

    /// 获取 HEAD 版本的文件内容。
    static func baseContent(
        workingDirectory: String,
        path: String
    ) async -> String? {
        let exists = await fileExistsInHEAD(workingDirectory: workingDirectory, path: path)
        guard exists else { return nil }
        let result = await runGit(
            args: ["show", "HEAD:\(path)"],
            workingDirectory: workingDirectory
        )
        return result.exitCode == 0 ? result.stdout : nil
    }

    /// 判断 HEAD 中是否存在指定文件。
    static func fileExistsInHEAD(
        workingDirectory: String,
        path: String
    ) async -> Bool {
        let result = await runGit(
            args: ["cat-file", "-e", "HEAD:\(path)"],
            workingDirectory: workingDirectory
        )
        return result.exitCode == 0
    }

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

    /// 拒绝整文件修改：将文件还原为 HEAD 版本（新增文件会被删除）。
    ///
    /// 使用 `checkout HEAD -- path` 而非 `checkout -- path`，因为后者只会用暂存区覆盖工作区；
    /// 若文件已暂存，则无法真正还原到 HEAD。
    @discardableResult
    static func rejectFile(
        workingDirectory: String,
        path: String
    ) async -> Bool {
        let result = await runGit(
            args: ["checkout", "HEAD", "--", path],
            workingDirectory: workingDirectory
        )
        return result.exitCode == 0
    }

    /// 接受整文件修改：将文件加入暂存区。
    @discardableResult
    static func acceptFile(
        workingDirectory: String,
        path: String
    ) async -> Bool {
        let result = await runGit(
            args: ["add", path],
            workingDirectory: workingDirectory
        )
        return result.exitCode == 0
    }

    /// 把文本原子写回文件。
    @discardableResult
    static func writeFile(
        at path: String,
        content: String
    ) -> Bool {
        let url = URL(fileURLWithPath: path)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            DMLogger.error("GitCommandService: 写文件失败 \(path): \(error.localizedDescription)", name: "GitCommandService")
            return false
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
