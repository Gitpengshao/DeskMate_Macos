import SwiftUI

/// 会话侧边栏 — 整体黑白风格设计。
struct SessionSidebar: View {
    @ObservedObject var sessionVM: SessionListViewModel
    let activeSessionId: String?
    let isDark: Bool
    @Binding var searchText: String
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 标题 + 新建按钮
            header

            // 搜索框
            searchField

            // 分隔
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1)
                .padding(.horizontal, 12)

            // 会话列表
            if sessionVM.state.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Palette.textPrimary)
                    Text("加载中…")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessionVM.state.filteredSessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 22))
                        .foregroundColor(Palette.textTertiary)
                    Text("暂无会话记录")
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textSecond)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sessionVM.state.filteredSessions) { session in
                            SessionItem(
                                session: session,
                                isActive: session.id == activeSessionId,
                                isDark: isDark,
                                onTap: { onSelect(session.id) },
                                onDelete: { onDelete(session.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }

            // 刷新按钮
            refreshButton
        }
        .frame(width: 260)
        .background(Palette.bgPanel)
        .overlay(
            Rectangle()
                .fill(Palette.border)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 13))
                .foregroundColor(Palette.textPrimary)
            Text("会话")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Palette.textTertiary)
                .font(.system(size: 11))
            TextField("搜索会话…", text: $searchText)
                .font(.system(size: 12))
                .foregroundColor(Palette.textPrimary)
                .onChange(of: searchText) { _, newValue in
                    sessionVM.updateSearch(newValue)
                }
                .textFieldStyle(.plain)
                .tint(Palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.bgBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Palette.border, lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Refresh

    private var refreshButton: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11))
            Text("刷新会话")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(Palette.textSecond)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color.clear)
                .overlay(
                    Rectangle()
                        .fill(Palette.border)
                        .frame(height: 1),
                    alignment: .top
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onRefresh() }
        .onHover { h in
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

/// 会话列表项 — 整体黑白风格设计。
struct SessionItem: View {
    let session: SessionRow
    let isActive: Bool
    let isDark: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    private var fillColor: Color {
        if isActive { return Palette.inverse }   // 选中：白底
        if isHovered { return Palette.bgHover }  // 悬停：暗灰
        return .clear
    }
    private var textColor: Color {
        isActive ? Palette.inverseInk : Palette.textPrimary
    }
    private var subColor: Color {
        isActive ? Palette.inverseInk.opacity(0.55) : Palette.textTertiary
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sessionTitleText)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(subColor)
                        .lineLimit(1)
                }
                Spacer()
                if isActive {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(Palette.inverseInk)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fillColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var sessionTitleText: String {
        let text: String
        if !session.preview.isEmpty {
            text = session.preview
        } else if !session.title.isEmpty {
            text = session.title
        } else {
            text = session.id
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 24 ? String(trimmed.prefix(24)) + "..." : trimmed
    }

    private var subtitleText: String {
        if !session.startedAt.isEmpty {
            return formatTime(session.startedAt)
        }
        return ""
    }

    private func formatTime(_ timestamp: String) -> String {
        if let seconds = Double(timestamp) {
            let date = Date(timeIntervalSince1970: seconds)
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm"
            return f.string(from: date)
        }
        return timestamp
    }
}

// MARK: - Palette

private enum Palette {
    static let bgBase      = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let bgPanel     = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let bgHover     = Color(red: 0.110, green: 0.110, blue: 0.110)
    static let border      = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let textPrimary = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond  = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
    static let inverse     = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let inverseInk  = Color(red: 0.000, green: 0.000, blue: 0.000)
}
