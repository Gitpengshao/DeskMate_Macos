import SwiftUI

/// 记忆管理页。
///
/// 三个 Tab：
/// - **记忆**     — `~/.hermes/memories/MEMORY.md` 条目（agent permanent memory / notes）
/// - **用户画像** — `~/.hermes/memories/USER.md` 条目（user preferences）
/// - **灵魂画像** — `~/.hermes/SOUL.md` 文件（agent soul / personality，仅可修改）
///
/// UI 风格：黑白主题，灰阶区分层次，无圆角装饰边框。
struct MemoryManagementPage: View {
    @StateObject private var viewModel = MemoryManagementViewModel()

    // 编辑/新增弹窗状态
    @State private var showAddSheet: Bool = false
    @State private var editingEntry: MemoryEntry? = nil
    @State private var deletingEntry: MemoryEntry? = nil

    var body: some View {
        ZStack {
            MMPalette.bgBase.ignoresSafeArea()
            VStack(spacing: 0) {
                pageHeader
                MMTabBar(viewModel: viewModel)
                MMCapacityBar(
                    viewModel: viewModel,
                    onAdd: { showAddSheet = true }
                )
                if let error = viewModel.model.errorMessage {
                    MMErrorBanner(message: error) {
                        viewModel.clearError()
                    }
                }
                Divider().background(MMPalette.border)
                content
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAddSheet) {
            let target: MemoryTarget = {
                switch viewModel.model.activeTab {
                case .userProfile: return .user
                case .soulProfile: return .soul
                case .memory:      return .memory
                }
            }()
            MMEntryEditorSheet(
                viewModel: viewModel,
                target: target,
                editingEntry: nil
            )
        }
        .sheet(item: $editingEntry) { entry in
            MMEntryEditorSheet(
                viewModel: viewModel,
                target: entry.target,
                editingEntry: entry
            )
        }
        .sheet(item: $deletingEntry) { entry in
            MMDeleteConfirmDialog(viewModel: viewModel, entry: entry)
        }
        .onDisappear { viewModel.dispose() }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(MMPalette.textPrimary)
                    Text("记忆管理")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(MMPalette.textPrimary)
                }
                Text("管理 Agent 永久记忆、用户画像与灵魂画像")
                    .font(.system(size: 12))
                    .foregroundColor(MMPalette.textMuted)
            }
            Spacer()
            Button(action: {
                Task {
                    switch viewModel.model.activeTab {
                    case .memory:      await viewModel.loadMemories()
                    case .userProfile: await viewModel.loadUserProfile()
                    case .soulProfile: await viewModel.loadSoulProfile()
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("刷新")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(MMPalette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(MMPalette.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MMPalette.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.model.activeTab {
        case .memory:
            memoryTabContent
        case .userProfile:
            userProfileTabContent
        case .soulProfile:
            soulProfileTabContent
        }
    }

    // MEMORY.md Tab
    @ViewBuilder
    private var memoryTabContent: some View {
        if viewModel.model.isLoadingMemories {
            MMLoadingView(title: MMText.loadingMemories)
        } else if viewModel.model.memoryEntries.isEmpty {
            MMEmptyView(icon: "tray", title: MMText.emptyMemory)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.model.memoryEntries.enumerated()), id: \.element.id) { idx, entry in
                        MMMemoryItemRow(
                            index: idx + 1,
                            entry: entry,
                            canDelete: true,
                            onEdit: { editingEntry = entry },
                            onDelete: { deletingEntry = entry }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    // USER.md Tab
    @ViewBuilder
    private var userProfileTabContent: some View {
        if viewModel.model.isLoadingUserProfile {
            MMLoadingView(title: MMText.loadingPersonas)
        } else if viewModel.model.userProfileEntries.isEmpty {
            MMEmptyView(icon: "person.crop.circle", title: MMText.emptyPersona)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.model.userProfileEntries.enumerated()), id: \.element.id) { idx, entry in
                        MMMemoryItemRow(
                            index: idx + 1,
                            entry: entry,
                            canDelete: true,
                            onEdit: { editingEntry = entry },
                            onDelete: { deletingEntry = entry }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    // SOUL.md Tab
    @ViewBuilder
    private var soulProfileTabContent: some View {
        if viewModel.model.isLoadingSoulProfile {
            MMLoadingView(title: MMText.loadingSoul)
        } else if viewModel.model.soulProfileEntries.isEmpty {
            soulEmptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.model.soulProfileEntries) { entry in
                        MMMemoryItemRow(
                            index: 1,
                            entry: entry,
                            canDelete: false,
                            onEdit: { editingEntry = entry },
                            onDelete: {}
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    private var soulEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(MMPalette.textMuted)
            Text(MMText.emptySoul)
                .font(.system(size: 13))
                .foregroundColor(MMPalette.textMuted)
            Button(action: {
                editingEntry = MemoryEntry(target: .soul, index: 0, content: "")
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                    Text("编辑灵魂画像")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(MMPalette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(MMPalette.bgHover)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MMPalette.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
struct MemoryManagementPage_Previews: PreviewProvider {
    static var previews: some View {
        MemoryManagementPage()
            .frame(width: 800, height: 600)
    }
}
#endif
