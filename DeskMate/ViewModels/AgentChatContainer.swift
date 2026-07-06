import Foundation
import SwiftUI

/// 按 profile 缓存的聊天相关 ViewModel 容器。
///
/// `AgentViewModel` 为每个选中的智能体维护一个容器，保证切换回来时
/// 会话状态、SSE 流、侧边栏状态不丢失，同时避免频繁重建 GatewayClient。
@MainActor
final class AgentChatContainer {
    let profileId: String
    let chatVM: AiChatViewModel
    let sessionVM: SessionListViewModel

    init(profileId: String, chatVM: AiChatViewModel, sessionVM: SessionListViewModel) {
        self.profileId = profileId
        self.chatVM = chatVM
        self.sessionVM = sessionVM
    }
}
