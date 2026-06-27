import Foundation

/// Sidebar navigation item — mirrors Flutter `SidebarNavItem`.
struct SidebarNavItem: Identifiable, Equatable {
    let id: String
    let labelKey: String
    let iconName: String
    let sectionKey: String
}

/// Main page data model — mirrors Flutter `MainModel`.
struct MainModel: Equatable {
    var activeNavId: String
    let navItems: [SidebarNavItem]

    static let `default` = MainModel(
        activeNavId: "ai-chat",
        navItems: []
    )
}
