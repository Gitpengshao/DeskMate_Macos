import SwiftUI
import AppKit

// MARK: - New Task Dialog

/// 新建任务对话框 — 对齐 Flutter `_NewTaskDialog`。
struct TBNewTaskDialog: View {
    @ObservedObject var viewModel: TaskBoardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var assignee: String = ""
    @State private var workspace: String = NSHomeDirectory()
    @State private var branch: String = ""
    @State private var tenant: String = "default"
    @State private var maxRetries: String = ""
    @State private var priority: String = "P2"
    @State private var status: String = "todo"
    @State private var skillsInput: String = ""

    /// 全部可选技能列表 — 通过 SkillManagementViewModel 注入
    var availableSkills: [TBSkillItem] = []

    /// 优先级候选项 — 对齐 Flutter `_priorityOptions`。
    private let priorityOptions = ["P0", "P1", "P2", "P3", "P4", "P5"]
    /// 状态候选项 — 对齐 Flutter `_statusOptions`（CLI 仅支持 blocked / running，todo 为默认）。
    private let statusOptions: [(String, TaskStatus)] = [
        ("todo", .todo),
        ("running", .running),
        ("blocked", .blocked),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — 顶部独立区域，与正文、操作栏用 Divider 切开
            VStack(alignment: .leading, spacing: 4) {
                Text(TBText.newTask)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(TBPalette.textPrimary)
                Text("填写任务信息后即可在看板中跟踪执行进度")
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

            // Scrollable form
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // 基础信息
                    TBDialogSection(title: "基础信息") {
                        VStack(alignment: .leading, spacing: 14) {
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
                                TBFieldLabel(label: TBText.assignee, required: false)
                                TBTextInputField(
                                    text: $assignee,
                                    placeholder: "负责人邮箱或名称",
                                    isMultiline: false
                                )
                            }

                            HStack(alignment: .top, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    TBFieldLabel(label: TBText.priority, required: false)
                                    TBChoicePicker(
                                        options: priorityOptions,
                                        selection: $priority
                                    )
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    TBFieldLabel(label: TBText.status, required: false)
                                    TBChoicePicker(
                                        options: statusOptions.map { $0.0 },
                                        selection: $status
                                    )
                                }
                            }
                        }
                    }

                    // 执行环境
                    TBDialogSection(title: "执行环境") {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .top, spacing: 14) {
                                VStack(alignment: .leading, spacing: 6) {
                                    TBFieldLabel(label: TBText.workspace, required: false)
                                    TBDirectoryPicker(text: $workspace)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    TBFieldLabel(label: TBText.branch, required: false)
                                    TBTextInputField(
                                        text: $branch,
                                        placeholder: "main",
                                        isMultiline: false
                                    )
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                TBFieldLabel(label: TBText.tenant, required: false)
                                TBTextInputField(
                                    text: $tenant,
                                    placeholder: "default",
                                    isMultiline: false
                                )
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                TBFieldLabel(label: TBText.skills, required: false)
                                TBMultiSkillPicker(
                                    availableSkills: availableSkills,
                                    skillsInput: $skillsInput
                                )
                            }
                        }
                    }

                    // 高级选项
                    TBDialogSection(title: "高级选项") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                TBFieldLabel(label: TBText.maxRetries, required: false)
                                TBTextInputField(
                                    text: $maxRetries,
                                    placeholder: "3",
                                    isMultiline: false
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 560)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)

            // Action toolbar — 底部固定工具栏，与正文明确分隔
            HStack(spacing: 10) {
                Spacer()
                Button(TBText.cancel) { dismiss() }
                    .buttonStyle(TBStatusButtonStyle(color: TBPalette.textMuted))
                Button(TBText.create) { submit() }
                    .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusComplete))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(TBPalette.bgBase)
        }
        .frame(width: 560)
        .background(TBPalette.bgBase)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(TBPalette.border, lineWidth: 1)
        )
    }

    private func submit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let statusEnum = statusOptions.first(where: { $0.0 == status })?.1 ?? .todo
        let skills: [String] = skillsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let maxRetriesInt: Int? = maxRetries.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : Int(maxRetries.trimmingCharacters(in: .whitespaces))

        Task {
            await viewModel.addTask(
                trimmedTitle,
                status: statusEnum,
                priority: priority,
                assignee: assignee,
                body: body_,
                workspace: workspace,
                tenant: tenant,
                branch: branch,
                skills: skills,
                maxRetries: maxRetriesInt
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

// MARK: - Form Helpers

/// 字段标签 — 对齐 Flutter `_FieldLabel`。
struct TBFieldLabel: View {
    let label: String
    var required: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TBPalette.textPrimary)
            if required {
                Text(TBText.required)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TBPalette.statusDanger)
            }
        }
    }
}

/// 分组容器 — 用于把表单字段按主题分组，给弹窗增加视觉层次。
struct TBDialogSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TBPalette.textHeader)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Rectangle()
                    .fill(TBPalette.divider)
                    .frame(height: 1)
            }
            content()
        }
    }
}

/// 文本输入框 — 单行/多行复用。
struct TBTextInputField: View {
    @Binding var text: String
    let placeholder: String
    var isMultiline: Bool = false

    var body: some View {
        if isMultiline {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundColor(TBPalette.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .foregroundColor(TBPalette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .frame(height: 88)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(TBPalette.inputBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TBPalette.border, lineWidth: 1)
            )
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(TBPalette.textPrimary)
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
    }
}

/// 单选下拉 — 对齐 Flutter `Select<String>`。
struct TBChoicePicker: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(opt) { selection = opt }
            }
        } label: {
            HStack {
                Text(selection)
                    .font(.system(size: 13))
                    .foregroundColor(TBPalette.textPrimary)
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
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 目录选择器 — 对齐 Flutter `_DirectoryPicker`。
struct TBDirectoryPicker: View {
    @Binding var text: String

    var body: some View {
        Button(action: pickDirectory) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .foregroundColor(TBPalette.textMuted)
                Text(text.isEmpty ? TBText.selectDirectory : text)
                    .font(.system(size: 13))
                    .foregroundColor(
                        text.isEmpty ? TBPalette.textMuted : TBPalette.textPrimary
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
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
        .buttonStyle(.plain)
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择工作目录"
        if panel.runModal() == .OK, let url = panel.url {
            text = url.path
        }
    }
}

/// 技能多选 — 简化版：提供建议 chip + 自由输入，逗号分隔。
/// Flutter 端是复杂的 `_buildSkillsList`，这里保留等价的可用 UI。
struct TBMultiSkillPicker: View {
    let availableSkills: [TBSkillItem]
    @Binding var skillsInput: String

    private let suggested = ["general", "creative", "apple", "blockchain", "git"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TBTextInputField(
                text: $skillsInput,
                placeholder: "用逗号分隔，例如: general, creative",
                isMultiline: false
            )
            if !availableSkills.isEmpty {
                FlowLayout(spacing: 6, runSpacing: 6) {
                    ForEach(suggested, id: \.self) { s in
                        Button {
                            appendSkill(s)
                        } label: {
                            Text("+\(s)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TBPalette.textMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(TBPalette.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func appendSkill(_ skill: String) {
        let list = skillsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if list.contains(skill) { return }
        if skillsInput.isEmpty {
            skillsInput = skill
        } else {
            skillsInput = list.joined(separator: ", ") + ", " + skill
        }
    }
}
