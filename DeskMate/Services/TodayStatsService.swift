import Foundation

/// 今日聊天汇总数据聚合服务。
///
/// 从 Hermes Gateway `/api/sessions` 拉取会话列表，按今日过滤后聚合：
/// - 聊天次数（今日活跃会话数）
/// - 输入 token 总数
/// - 输出 token 总数
///
/// 所有拉取与聚合逻辑均在后台线程执行，不依赖 @MainActor。
final class TodayStatsService {

    private let apiService: SessionApiService

    init(client: GatewayClient = .shared) {
        self.apiService = SessionApiService(client: client)
    }

    /// 拉取并聚合今日汇总数据。
    func fetchTodayStats() async -> TodayStats {
        let sessions = await apiService.fetchSessions()

        DMLogger.log(
            "TodayStatsService: fetched \(sessions.count) sessions",
            name: "TodayStatsService"
        )

        let calendar = Calendar.current
        var chatCount = 0
        var inputTokens = 0
        var outputTokens = 0

        for session in sessions {
            let rawDate = session.lastActive.isEmpty ? session.startedAt : session.lastActive
            let parsedDate = parseDate(rawDate)
            let isToday = parsedDate.map { calendar.isDateInToday($0) } ?? false

            DMLogger.log(
                "TodayStatsService session: " +
                "id=\(session.id), " +
                "last_active=\(session.lastActive), " +
                "started_at=\(session.startedAt), " +
                "ended_at=\(session.endedAt), " +
                "input_tokens=\(session.inputTokens), " +
                "output_tokens=\(session.outputTokens), " +
                "message_count=\(session.messageCount), " +
                "parsedDate=\(parsedDate?.description ?? "nil"), " +
                "isToday=\(isToday)",
                name: "TodayStatsService"
            )

            guard isToday else { continue }

            chatCount += 1
            inputTokens += session.inputTokens
            outputTokens += session.outputTokens
        }

        DMLogger.log(
            "TodayStatsService result: chatCount=\(chatCount), " +
            "inputTokens=\(inputTokens), outputTokens=\(outputTokens)",
            name: "TodayStatsService"
        )

        return TodayStats(
            chatCount: chatCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    // MARK: - Private

    /// 兼容解析后端返回的时间字段。
    ///
    /// 后端历史数据可能为 Unix 时间戳秒字符串（参考 `SessionSidebar.formatTime`），
    /// 也可能为 ISO8601 字符串（参考 `TaskBoardModel` 的日期解析）。
    private func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }

        // 1. Unix 时间戳秒（或毫秒）
        if let seconds = Double(value) {
            // 毫秒时间戳（13 位）vs 秒时间戳（10 位）
            let interval = seconds > 1_000_000_000_000 ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: interval)
        }

        // 2. ISO8601
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) { return date }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: value) { return date }

        // 3. 常见日期格式兜底
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd"
        ]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }

        return nil
    }
}
