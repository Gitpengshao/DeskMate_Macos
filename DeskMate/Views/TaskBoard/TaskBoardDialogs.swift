import SwiftUI
import AppKit

// MARK: - New Task Dialog

/// 新建任务对话框 — 只保留最核心字段：标题、描述、Agent 下拉。
struct TBNewTaskDialog: View {
    @ObservedObject var viewModel: TaskBoardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var selectedAgentId: String = ""

    private var selectedAgent: AgentProfile? {
        viewModel.agentProfiles.first(where: { $0.id == selectedAgentId })
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !selectedAgentId.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(TBText.newTask)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(TBPalette.textPrimary)
                Text("选择一个 Agent 并告诉它要做什么")
                    .font(.system(size: 12))
                    .foregroundColor(TBPalette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .background(TBPalette.bgBase)

            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    TBFieldLabel(label: TBText.taskTitle, required: true)
                    TBTextInputField(
                        text: $title,
                        placeholder: "例如：实现登录页 UI",
                        isMultiline: false
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    TBFieldLabel(label: TBText.taskBody, required: false)
                    TBTextInputField(
                        text: $body_,
                        placeholder: "补充任务背景、目标与验收标准",
                        isMultiline: true
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    TBFieldLabel(label: TBText.assignee, required: true)
                    agentPicker
                }

                if viewModel.agentProfiles.isEmpty {
                    Text("尚未创建任何 Agent，请先前往 Agent 管理页面创建。")
                        .font(.system(size: 12))
                        .foregroundColor(TBPalette.statusBlock)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)

            HStack(spacing: 10) {
                Spacer()
                Button(TBText.cancel) { dismiss() }
                    .buttonStyle(TBStatusButtonStyle(color: TBPalette.textMuted))
                Button(TBText.create) { submit() }
                    .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusComplete))
                    .disabled(!canSubmit)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(TBPalette.bgBase)
        }
        .frame(width: 420)
        .background(TBPalette.bgBase)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(TBPalette.border, lineWidth: 1)
        )
    }

    private var agentPicker: some View {
        let profiles = viewModel.agentProfiles
        return Menu {
            ForEach(profiles) { profile in
                Button(profile.displayTitle) {
                    selectedAgentId = profile.id
                }
            }
        } label: {
            HStack {
                Text(selectedAgent?.displayTitle ?? "选择 Agent")
                    .font(.system(size: 13))
                    .foregroundColor(
                        selectedAgent == nil ? TBPalette.textMuted : TBPalette.textPrimary
                    )
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(TBPalette.textMuted)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(TBPalette.inputBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TBPalette.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(profiles.isEmpty)
    }

    private func submit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, let agent = selectedAgent else { return }

        Task {
            await viewModel.addTask(
                trimmedTitle,
                status: .todo,
                priority: "P2",
                assignee: agent.id,
                body: body_,
                workspace: viewModel.defaultWorkspace(for: agent),
                tenant: "default"
            )
            await MainActor.run { dismiss() }
        }
    }
}

// MARK: - Switch Board Dialog

/// 切换看板对话框 — 对齐官方 dashboard 顶部 board switcher。
///
/// 每个看板卡支持右键 / `…` 菜单执行重命名 / 归档(对齐官方
/// `boards rename` / `boards rm`)。default 看板不显示归档项
/// (官方 dashboard 同样只在非 default 看板上展示 Archive)。
struct TBSwitchBoardDialog: View {
    let boards: [TaskBoard]
    let activeBoardId: String
    @ObservedObject var viewModel: TaskBoardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var renamingBoardId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(TBText.switchBoard)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(TBPalette.textPrimary)
                Text("选择一个看板作为当前工作面板 · 右键卡片可重命名 / 归档")
                    .font(.system(size: 12))
                    .foregroundColor(TBPalette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .background(TBPalette.bgBase)

            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)

            // Content
            Group {
                if boards.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 22))
                            .foregroundColor(TBPalette.textMuted)
                        Text(TBText.empty)
                            .font(.system(size: 12))
                            .foregroundColor(TBPalette.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
                } else {
                    FlowLayout(spacing: 10, runSpacing: 10) {
                        ForEach(boards) { board in
                            boardCard(board: board)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)

            // Footer toolbar
            HStack(spacing: 10) {
                Spacer()
                Button(TBText.close) { dismiss() }
                    .buttonStyle(TBStatusButtonStyle(color: TBPalette.textMuted))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(TBPalette.bgBase)
        }
        .frame(width: 440)
        .background(TBPalette.bgBase)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(TBPalette.border, lineWidth: 1)
        )
        .sheet(item: Binding(
            get: { renamingBoardId.map { RenameContext(id: $0) } },
            set: { renamingBoardId = $0?.id }
        )) { ctx in
            TBRenameBoardDialog(
                currentName: boards.first(where: { $0.id == ctx.id })?.name ?? "",
                onSave: { newName in
                    Task { await viewModel.renameBoard(ctx.id, newName: newName) }
                    renamingBoardId = nil
                },
                onCancel: { renamingBoardId = nil }
            )
        }
    }

    @ViewBuilder
    private func boardCard(board: TaskBoard) -> some View {
        let isActive = board.id == activeBoardId
        // default 看板不允许归档(官方 dashboard 同样如此)
        let canArchive = board.slug != "default"
        HStack(spacing: 6) {
            Button {
                Task {
                    await viewModel.switchBoard(board.id)
                    dismiss()
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(board.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(
                            isActive ? TBPalette.inverseInk : TBPalette.textPrimary
                        )
                    if !board.description.isEmpty {
                        Text(board.description)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(
                                isActive
                                    ? TBPalette.inverseInk.opacity(0.7)
                                    : TBPalette.textMuted
                            )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? TBPalette.inverse : TBPalette.bgElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isActive ? TBPalette.inverse : TBPalette.border,
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            // `…` 菜单 + 右键菜单:重命名 / 归档
            Menu {
                Button("重命名") {
                    renamingBoardId = board.id
                }
                if canArchive {
                    Button("归档", role: .destructive) {
                        Task { await viewModel.deleteBoard(board.id) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isActive ? TBPalette.inverseInk : TBPalette.textMuted)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .contextMenu {
            Button("重命名") {
                renamingBoardId = board.id
            }
            if canArchive {
                Button("归档", role: .destructive) {
                    Task { await viewModel.deleteBoard(board.id) }
                }
            }
        }
    }

    private struct RenameContext: Identifiable {
        let id: String
    }
}


