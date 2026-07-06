import Foundation

/// 灵动岛「今日汇总」数据结构。
struct TodayStats: Equatable {
    let chatCount: Int
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }
}
