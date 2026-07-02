import Foundation
import os

/// 日志工具类，封装中文日志打印，对齐 Flutter 的 `developer.log`。
///
/// 用法：
///   DMLogger.shared.log("开始环境检测", name: "OnboardingViewModel")
///   DMLogger.shared.error("安装失败", name: "OnboardingViewModel")
///
/// 日志会同时输出到 OSLog（Console.app 可查看）和 stdout。
enum DMLogger {

    // MARK: - Private

    private nonisolated static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// 统一输出日志
    private nonisolated static func emit(
        _ message: String,
        name: String,
        level: String,
        file: String = #file,
        line: Int = #line
    ) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let output = "[\(timestamp)] [\(level)] [\(name)] \(message)  ← \(fileName):\(line)"

        // OSLog
        let log = OSLog(subsystem: "com.deskmate", category: name)
        os_log("%{public}@", log: log, type: .default, output)

        // stdout 方便 Xcode console 查看
        print(output)
    }

    // MARK: - Public

    /// 普通日志（对应 Flutter developer.log）
    nonisolated static func log(
        _ message: String,
        name: String,
        file: String = #file,
        line: Int = #line
    ) {
        emit(message, name: name, level: "INFO", file: file, line: line)
    }

    /// 错误日志
    nonisolated static func error(
        _ message: String,
        name: String,
        file: String = #file,
        line: Int = #line
    ) {
        emit(message, name: name, level: "ERROR", file: file, line: line)
    }
}
