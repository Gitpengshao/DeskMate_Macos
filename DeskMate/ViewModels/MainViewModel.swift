import SwiftUI
import Combine

/// ViewModel for MainPage — mirrors Flutter `MainViewModel`.
@MainActor
final class MainViewModel: ObservableObject {
    /// 全局共享实例，供语音快捷键等需要切换导航的模块使用。
    static let shared = MainViewModel()

    @Published var model: MainModel

    // MARK: Section ordering (matches Flutter)
    let sectionOrder = [
        "sidebarMainInterface",
        "sidebarPetManagement",
        "sidebarTools",
        "sidebarOther",
    ]

    // MARK: Section labels (hardcoded, no l10n for now)
    func sectionLabel(_ key: String) -> String {
        switch key {
        case "sidebarMainInterface":   return "主界面"
        case "sidebarPetManagement":   return "宠物管理"
        case "sidebarTools":           return "工具"
        case "sidebarOther":           return "其他"
        default:                       return key
        }
    }

    // MARK: Item display labels
    func itemLabel(_ id: String) -> String {
        switch id {
        case "ai-chat":             return "AI 对话"
        case "agent":               return "智能体"
        case "memory-management":   return "记忆管理"
        case "task-board":          return "任务看板"
        case "model-config":        return "模型配置"
        case "skill-management":    return "技能管理"
        case "gateway-config":      return "网关配置"
        case "settings":            return "设置"
        default:                    return id
        }
    }

    // MARK: Grouped nav items (computed)
    var groupedItems: [(sectionKey: String, items: [SidebarNavItem])] {
        var groups: [(sectionKey: String, items: [SidebarNavItem])] = []
        for sectionKey in sectionOrder {
            let items = model.navItems.filter { $0.sectionKey == sectionKey }
            if !items.isEmpty {
                groups.append((sectionKey, items))
            }
        }
        return groups
    }

    init() {
        self.model = MainModel(
            activeNavId: "ai-chat",
            navItems: [
                // 主界面
                SidebarNavItem(id: "ai-chat", labelKey: "sidebarAiChat", iconName: "message", sectionKey: "sidebarMainInterface"),
                // 宠物管理
                SidebarNavItem(id: "agent", labelKey: "sidebarAgent", iconName: "person.2.fill", sectionKey: "sidebarPetManagement"),
                SidebarNavItem(id: "memory-management", labelKey: "sidebarMemoryManagement", iconName: "brain", sectionKey: "sidebarPetManagement"),
                // 工具
                SidebarNavItem(id: "task-board", labelKey: "sidebarTaskBoard", iconName: "rectangle.split.3x1", sectionKey: "sidebarTools"),
                SidebarNavItem(id: "model-config", labelKey: "sidebarModelConfig", iconName: "cpu", sectionKey: "sidebarTools"),
                SidebarNavItem(id: "skill-management", labelKey: "sidebarSkillManagement", iconName: "sparkles", sectionKey: "sidebarTools"),
                SidebarNavItem(id: "gateway-config", labelKey: "sidebarGatewayConfig", iconName: "antenna.radiowaves.left.and.right", sectionKey: "sidebarTools"),
                // 其他
                SidebarNavItem(id: "settings", labelKey: "sidebarSettings", iconName: "gear", sectionKey: "sidebarOther"),
            ]
        )
    }

    /// Switch active navigation item — mirrors Flutter `switchNav`.
    func switchNav(_ navId: String) {
        model.activeNavId = navId
    }
}
