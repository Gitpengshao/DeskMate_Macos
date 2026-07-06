import SwiftUI
import AppKit
import Combine

// MARK: - 灵动岛内容视图

/// 灵动岛内显示的自定义内容 — 黑白主题，简洁美观
/// 通过 `@ObservedObject manager` 响应加载状态切换，避免点击后灵动岛消失。
struct DeskMateNotchContent: View {
    @ObservedObject var manager: DynamicNotchManager
    let onOpenConsole: () -> Void

    @State private var isHovering = false
    @Environment(\.notchSection) private var notchSection

    var body: some View {
        if manager.isLoading {
            // 加载中视图：点击后立即展示，避免卡顿无反馈
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)

                VStack(alignment: .leading, spacing: 1) {
                    Text("DeskMate")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("正在打开控制台…")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minWidth: 240, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        } else if manager.isWorking {
            // 工作态视图：AI 流式输出期间播放 work 精灵动画 + 文字
            HStack(spacing: 14) {
                SpriteFrameAnimationView(
                    config: PetAnimation.work.config,
                    fps: 18,
                    displaySize: 60
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("DeskMate")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("努力工作中")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.65))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minWidth: 240, minHeight: 80, alignment: .leading)
            .contentShape(Rectangle())
        } else if manager.isConsoleOpen && notchSection == .expanded {
            // 控制台打开期间悬浮展开：展示今日汇总
            TodaySummaryView(manager: manager)
        } else {
            Button(action: onOpenConsole) {
                HStack(spacing: 12) {
                    // 左侧图标
                    Image(nsImage: notchIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    // 中间文字
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DeskMate")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("点击打开控制台")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    Spacer(minLength: 0)

                    // 右侧箭头
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .offset(x: isHovering ? 3 : 0)
                        .animation(.easeOut(duration: 0.2), value: isHovering)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(minWidth: 240, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle())
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }

    /// 使用 AppIcon 作为 notch 图标
    private var notchIcon: NSImage {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            return icon
        }
        // 回退：生成一个简单的圆形图标
        return generateFallbackIcon()
    }

    private func generateFallbackIcon() -> NSImage {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 64, height: 64))
        path.fill()
        image.unlockFocus()
        return image
    }
}

// MARK: - 今日汇总视图

private struct TodaySummaryView: View {
    @ObservedObject var manager: DynamicNotchManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text("今日汇总")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 0)

                if manager.isFetchingTodayStats {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }

            if let stats = manager.todayStats {
                HStack(spacing: 14) {
                    SummaryItem(title: "对话", value: "\(formatCompact(stats.chatCount)) 次")
                    SummaryItem(title: "输入", value: formatCompact(stats.inputTokens))
                    SummaryItem(title: "输出", value: formatCompact(stats.outputTokens))
                    SummaryItem(title: "总计", value: formatCompact(stats.totalTokens))
                }
            } else {
                Text("正在加载今日数据…")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minWidth: 280, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
        .task {
            await manager.refreshTodayStats()
        }
    }
}

private struct SummaryItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

/// 将大数字压缩为 k 单位显示。
/// - 小于 1000 显示原值，如 `999`。
/// - 大于等于 1000 显示为 `1.2k`、`15k` 等，整数时不保留小数。
private func formatCompact(_ value: Int) -> String {
    guard value >= 1000 else { return "\(value)" }
    let k = Double(value) / 1000.0
    if k == floor(k) {
        return "\(Int(k))k"
    }
    return String(format: "%.1fk", k)
}

// MARK: - 按钮样式

private struct NotchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - 灵动岛管理器

/// 管理 DynamicNotchKit 灵动岛的显示与隐藏。
///
/// 设计要点：
/// 1. 灵动岛常驻 — 点击打开控制台时不会隐藏灵动岛，仅切换为加载状态，
///    控制台就绪后收起到 compact 模式，实例始终保留。
/// 2. 加载反馈 — 控制台窗口采用预加载策略；若未就绪则在灵动岛内展示 loading，
///    避免点击后无响应的卡顿感。
/// 3. 工作态 — AI 流式输出期间灵动岛展开并播放 work 精灵动画，
///    流结束后收回到 compact 状态。
/// 4. 控制台打开期间 — 鼠标悬浮展开时展示今日汇总，数据在后台刷新。
@MainActor
final class DynamicNotchManager: ObservableObject {
    /// 全局单例 — 业务侧（AiChatViewModel 等）可直接访问，无需经过 AppDelegate。
    static let shared = DynamicNotchManager()

    /// 是否正在打开控制台 — 用于在灵动岛内展示 loading
    @Published var isLoading: Bool = false

    /// 是否处于 AI 工作态 — 流式输出期间为 true，驱动灵动岛展开 work 动画
    @Published var isWorking: Bool = false

    /// 控制台窗口当前是否处于打开状态
    @Published var isConsoleOpen: Bool = false

    /// 今日汇总数据
    @Published var todayStats: TodayStats?

    /// 是否正在后台拉取今日汇总
    @Published var isFetchingTodayStats: Bool = false

    /// 灵动岛实例 — 常驻，不销毁
    private var currentNotch: DynamicNotch<DeskMateNotchContent, AnyView, AnyView>?

    /// 今日汇总聚合服务
    private let todayStatsService = TodayStatsService()

    /// 防止并发重复刷新
    private var statsRefreshTask: Task<Void, Never>?

    /// 点击灵动岛回调
    var onOpenConsole: (() -> Void)?

    /// 显示灵动岛（幂等：若实例已存在则恢复显示，不重复创建）
    func show() {
        ensureNotch()
        Task { [weak self] in
            await self?.currentNotch?.compact()
        }
    }

    /// 同步创建 / 复用灵动岛实例 — 抽出便于 startWorking() 等其它入口复用。
    private func ensureNotch() {
        if currentNotch != nil { return }

        let content = DeskMateNotchContent(manager: self) { [weak self] in
            self?.handleClick()
        }

        let notch = DynamicNotch(
            hoverBehavior: .keepVisible,
            style: .auto,
            expanded: { content },
            compactLeading: {
                AnyView(
                    HStack(spacing: 4) {
                        Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                        Text("DeskMate")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                    }
                )
            },
            compactTrailing: {
                AnyView(
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                )
            }
        )
        currentNotch = notch
    }

    /// 进入工作态 — 展开灵动岛并切换到 work 动画视图。幂等。
    func startWorking() {
        guard !isWorking else { return }
        isWorking = true
        ensureNotch()
        Task { [weak self] in
            await self?.currentNotch?.expand()
        }
    }

    /// 退出工作态 — 收回到 compact 状态。幂等。
    func stopWorking() {
        guard isWorking else { return }
        isWorking = false
        Task { [weak self] in
            await self?.currentNotch?.compact()
        }
    }

    /// 点击灵动岛：保持灵动岛常驻，仅切换为加载状态并触发打开控制台
    private func handleClick() {
        // 立即进入加载状态，给用户即时反馈
        isLoading = true
        // 触发回调，打开控制台（控制台就绪后会调用 consoleDidOpen）
        onOpenConsole?()
    }

    /// 控制台已打开：清除加载状态并收起到 compact，保持灵动岛常驻。
    /// 控制台打开期间仍允许鼠标悬浮展开，展开后展示今日汇总。
    func consoleDidOpen() {
        isLoading = false
        isConsoleOpen = true
        Task { [weak self] in
            // 收起到 compact，后续由用户悬浮触发展开并展示汇总
            await self?.currentNotch?.compact()
        }
    }

    /// 控制台已关闭：恢复初始状态
    func consoleDidClose() {
        isConsoleOpen = false
        todayStats = nil
    }

    /// 后台刷新今日汇总数据，完成后更新 `todayStats`。
    ///
    /// - 使用 `Task.detached` 在后台线程执行拉取与聚合，避免阻塞主线程。
    /// - 带有并发保护，避免重复请求。
    func refreshTodayStats() {
        guard !isFetchingTodayStats else { return }

        statsRefreshTask?.cancel()
        statsRefreshTask = Task { [weak self] in
            guard let self = self else { return }

            await MainActor.run { self.isFetchingTodayStats = true }

            let stats = await Task.detached(priority: .utility) { [service = self.todayStatsService] in
                await service.fetchTodayStats()
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.todayStats = stats
                self.isFetchingTodayStats = false
            }
        }
    }

    /// 仅在必要时彻底隐藏（保留实例以便恢复）— 当前业务不再使用
    func hide() {
        Task { [weak self] in
            await self?.currentNotch?.hide()
        }
    }
}
