import SwiftUI

// MARK: - New Profile Dialog

/// 新建 / 克隆 profile 对话框 — 对齐 `hermes profile create` 的所有 flag。
struct NewAgentProfileDialog: View {
    @ObservedObject var viewModel: AgentViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMode: AgentCreateMode = .blank
    @State private var profileName: String = ""
    @State private var description: String = ""
    @State private var cloneFrom: String = ""
    @State private var errorText: String = ""

    /// 创建时的模型配置策略。
    @State private var modelSetupMode: AgentModelSetupMode = .followDefault
    /// 自定义模型配置弹窗的目标 profile（创建成功后设置）。
    @State private var profileNameToConfigure: String? = nil
    /// 是否显示自定义模型配置弹窗。
    @State private var showModelConfigSheet: Bool = false

    /// 可用作 `--clone-from` 源的已有 profile。
    private var cloneFromCandidates: [AgentProfile] {
        viewModel.model.profiles.filter { !$0.isDefault }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AgentPalette.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    modePicker
                    nameField
                    if selectedMode == .cloneFrom {
                        cloneFromPicker
                    }
                    descriptionField
                    modelSetupSection
                    if let err = errorText.isEmpty ? nil : errorText {
                        errorView(err)
                    }
                }
                .padding(20)
            }
            .disabled(viewModel.isSubmitting)

            Divider().overlay(AgentPalette.divider)
            footer
        }
        .frame(width: 520, height: 620)
        .background(AgentPalette.bgElevated)
        .sheet(isPresented: $showModelConfigSheet) {
            if let name = profileNameToConfigure {
                AddMainModelSheet(
                    viewModel: ModelConfigViewModel(profile: name),
                    onSaved: { dismiss() }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Text(AgentText.newProfileTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AgentPalette.textMuted)
                    .padding(6)
                    .background(
                        Circle().fill(AgentPalette.bgPanel)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("创建方式")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(AgentPalette.textMuted)
                .textCase(.uppercase)

            VStack(spacing: 6) {
                ForEach(AgentCreateMode.allCases) { mode in
                    modeRow(mode)
                }
            }
        }
    }

    private func modeRow(_ mode: AgentCreateMode) -> some View {
        let isSelected = selectedMode == mode
        return Button(action: { selectedMode = mode }) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? AgentPalette.inverseInk : AgentPalette.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? AgentPalette.inverse : AgentPalette.bgPanel)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(AgentPalette.textPrimary)
                    Text(mode.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(AgentPalette.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? AgentPalette.inverse : AgentPalette.textDisabled)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? AgentPalette.inverse.opacity(0.06) : AgentPalette.bgPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        isSelected ? AgentPalette.inverse.opacity(0.5) : AgentPalette.border,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Name Field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AgentText.fieldProfileName)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(AgentPalette.textMuted)
                .textCase(.uppercase)
            TextField("coder", text: $profileName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(AgentPalette.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AgentPalette.bgPanel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AgentPalette.border, lineWidth: 0.5)
                )
            Text("1-64 字符，小写字母数字 + 连字符 / 下划线，首字符必须为字母数字")
                .font(.system(size: 10.5))
                .foregroundColor(AgentPalette.textDisabled)
        }
    }

    // MARK: - Clone From Picker

    private var cloneFromPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AgentText.fieldCloneFrom)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(AgentPalette.textMuted)
                .textCase(.uppercase)
            Picker("", selection: $cloneFrom) {
                Text("请选择…").tag("")
                ForEach(cloneFromCandidates) { p in
                    Text("\(p.id) (\(p.displayTitle))").tag(p.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AgentPalette.bgPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AgentPalette.border, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Description

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AgentText.fieldDescription)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(AgentPalette.textMuted)
                .textCase(.uppercase)
            TextEditor(text: $description)
                .font(.system(size: 12, design: .default))
                .foregroundColor(AgentPalette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 60, maxHeight: 90)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AgentPalette.bgPanel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AgentPalette.border, lineWidth: 0.5)
                )
            Text(AgentText.fieldDescriptionHint)
                .font(.system(size: 10.5))
                .foregroundColor(AgentPalette.textDisabled)
        }
    }

    // MARK: - Model Setup

    private var modelSetupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("模型配置")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(AgentPalette.textMuted)
                .textCase(.uppercase)

            VStack(spacing: 6) {
                modelSetupRow(
                    mode: .followDefault,
                    title: "跟随 default 智能体",
                    subtitle: "复制默认 profile 的模型配置到新智能体"
                )
                modelSetupRow(
                    mode: .custom,
                    title: "自定义模型",
                    subtitle: "创建后为此智能体单独配置主模型"
                )
            }
        }
    }

    private func modelSetupRow(
        mode: AgentModelSetupMode,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = modelSetupMode == mode
        return Button(action: { modelSetupMode = mode }) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? AgentPalette.inverseInk : AgentPalette.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? AgentPalette.inverse : AgentPalette.bgPanel)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(AgentPalette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(AgentPalette.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? AgentPalette.inverse : AgentPalette.textDisabled)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? AgentPalette.inverse.opacity(0.06) : AgentPalette.bgPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        isSelected ? AgentPalette.inverse.opacity(0.5) : AgentPalette.border,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.20))
            Text(msg)
                .font(.system(size: 11.5))
                .foregroundColor(AgentPalette.textPrimary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.18, green: 0.13, blue: 0.06))
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button(AgentText.cancel) { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AgentPalette.textMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)

            Button(action: { submit() }) {
                HStack(spacing: 5) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(AgentText.create)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(AgentPalette.inverseInk)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(profileName.isEmpty || viewModel.isSubmitting ? AgentPalette.textDisabled : AgentPalette.inverse)
                )
            }
            .buttonStyle(.plain)
            .disabled(profileName.isEmpty || viewModel.isSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Submit

    private func submit() {
        let trimmed = profileName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorText = "请填写 profile 名"
            return
        }
        guard AgentService.validateProfileName(trimmed) else {
            errorText = AgentText.invalidName
            return
        }
        if selectedMode == .cloneFrom, cloneFrom.isEmpty {
            errorText = AgentText.noCloneFrom
            return
        }
        errorText = ""
        Task {
            await viewModel.createProfile(
                name: trimmed,
                mode: selectedMode,
                description: description.isEmpty ? nil : description,
                cloneFrom: selectedMode == .cloneFrom ? cloneFrom : nil,
                modelSetupMode: modelSetupMode
            )
            // 关闭对话框；自定义模型时在配置弹窗保存后再关闭
            if viewModel.model.errorMessage.isEmpty {
                if modelSetupMode == .custom {
                    profileNameToConfigure = trimmed
                    showModelConfigSheet = true
                } else {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Rename Dialog

/// 重命名 profile — 对齐 `hermes profile rename`。
struct RenameAgentProfileDialog: View {
    @ObservedObject var viewModel: AgentViewModel
    let profile: AgentProfile
    @Environment(\.dismiss) private var dismiss

    @State private var newName: String = ""
    @State private var errorText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AgentPalette.divider)
            VStack(alignment: .leading, spacing: 12) {
                Text("将 \(profile.id) 重命名为：")
                    .font(.system(size: 12))
                    .foregroundColor(AgentPalette.textMuted)
                TextField("新名称", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(AgentPalette.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AgentPalette.bgPanel)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AgentPalette.border, lineWidth: 0.5)
                    )
                Text("新名称会成为新的命令别名，slug 会同步更新")
                    .font(.system(size: 10.5))
                    .foregroundColor(AgentPalette.textDisabled)
                if !errorText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.20))
                        Text(errorText)
                            .font(.system(size: 11.5))
                            .foregroundColor(AgentPalette.textPrimary)
                    }
                }
            }
            .padding(20)
            .disabled(viewModel.isSubmitting)
            Divider().overlay(AgentPalette.divider)
            footer
        }
        .frame(width: 460, height: 260)
        .background(AgentPalette.bgElevated)
        .onAppear { newName = profile.id }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Text(AgentText.renameTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AgentPalette.textMuted)
                    .padding(6)
                    .background(Circle().fill(AgentPalette.bgPanel))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(AgentText.cancel) { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AgentPalette.textMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)
            Button(action: { submit() }) {
                HStack(spacing: 5) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(AgentText.save)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(AgentPalette.inverseInk)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(newName.isEmpty || viewModel.isSubmitting ? AgentPalette.textDisabled : AgentPalette.inverse)
                )
            }
            .buttonStyle(.plain)
            .disabled(newName.isEmpty || viewModel.isSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func submit() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorText = "请填写新名称"; return }
        guard AgentService.validateProfileName(trimmed) else {
            errorText = AgentText.invalidName
            return
        }
        if trimmed == profile.id {
            dismiss()
            return
        }
        errorText = ""
        Task {
            await viewModel.renameProfile(profile.id, to: trimmed)
            if viewModel.model.errorMessage.isEmpty { dismiss() }
        }
    }
}

// MARK: - Delete Confirmation Dialog

/// 删除 profile 确认 — 对齐 `hermes profile delete`。
struct DeleteAgentProfileDialog: View {
    @ObservedObject var viewModel: AgentViewModel
    let profile: AgentProfile
    @Environment(\.dismiss) private var dismiss

    @State private var confirmText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AgentPalette.divider)
            VStack(alignment: .leading, spacing: 14) {
                Text("此操作将永久删除以下 profile：")
                    .font(.system(size: 12))
                    .foregroundColor(AgentPalette.textMuted)

                profileSummary

                Text("请输入 profile 名 `\(profile.id)` 以确认删除")
                    .font(.system(size: 11.5))
                    .foregroundColor(AgentPalette.textMuted)
                TextField(profile.id, text: $confirmText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(AgentPalette.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AgentPalette.bgPanel)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AgentPalette.border, lineWidth: 0.5)
                    )
            }
            .padding(20)
            .disabled(viewModel.isSubmitting)
            Divider().overlay(AgentPalette.divider)
            footer
        }
        .frame(width: 520, height: 360)
        .background(AgentPalette.bgElevated)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.93, green: 0.30, blue: 0.30))
            Text(AgentText.deleteTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AgentPalette.textMuted)
                    .padding(6)
                    .background(Circle().fill(AgentPalette.bgPanel))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var profileSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Profile", profile.id)
            if !profile.path.isEmpty { row("路径", profile.path) }
            if !profile.model.isEmpty { row("模型", profile.model) }
            row("技能数", "\(profile.skillsCount)")
            if profile.isDistribution {
                row("Distribution", profile.distributionLabel)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(AgentPalette.bgPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AgentPalette.border, lineWidth: 0.5)
        )
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(k)
                .font(.system(size: 11))
                .foregroundColor(AgentPalette.textMuted)
                .frame(width: 78, alignment: .trailing)
            Text(v)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(AgentPalette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(AgentText.cancel) { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AgentPalette.textMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)
            Button(action: { submit() }) {
                HStack(spacing: 5) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(AgentText.deleteProfile)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Color.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(confirmText == profile.id && !viewModel.isSubmitting
                              ? Color(red: 0.78, green: 0.20, blue: 0.20)
                              : AgentPalette.textDisabled)
                )
            }
            .buttonStyle(.plain)
            .disabled(confirmText != profile.id || viewModel.isSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func submit() {
        guard confirmText == profile.id else { return }
        Task {
            await viewModel.deleteProfile(profile.id)
            if viewModel.model.errorMessage.isEmpty { dismiss() }
        }
    }
}

// MARK: - Edit Description Dialog

/// 编辑 description — 对齐 `hermes profile describe`。
struct DescribeAgentProfileDialog: View {
    @ObservedObject var viewModel: AgentViewModel
    let profile: AgentProfile
    @Environment(\.dismiss) private var dismiss

    @State private var description: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AgentPalette.divider)
            VStack(alignment: .leading, spacing: 10) {
                Text(AgentText.fieldDescription)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(AgentPalette.textMuted)
                    .textCase(.uppercase)
                TextEditor(text: $description)
                    .font(.system(size: 12))
                    .foregroundColor(AgentPalette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 120, maxHeight: 200)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AgentPalette.bgPanel)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AgentPalette.border, lineWidth: 0.5)
                    )
                Text(AgentText.fieldDescriptionHint)
                    .font(.system(size: 10.5))
                    .foregroundColor(AgentPalette.textDisabled)
            }
            .padding(20)
            .disabled(viewModel.isSubmitting)
            Divider().overlay(AgentPalette.divider)
            footer
        }
        .frame(width: 540, height: 320)
        .background(AgentPalette.bgElevated)
        .onAppear { description = profile.description }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Text("编辑描述 · \(profile.id)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AgentPalette.textMuted)
                    .padding(6)
                    .background(Circle().fill(AgentPalette.bgPanel))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(AgentText.cancel) { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AgentPalette.textMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)
            Button(action: { submit() }) {
                HStack(spacing: 5) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(AgentText.save)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(AgentPalette.inverseInk)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.isSubmitting ? AgentPalette.textDisabled : AgentPalette.inverse)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func submit() {
        Task {
            await viewModel.describeProfile(profile.id, description: description)
            if viewModel.model.errorMessage.isEmpty { dismiss() }
        }
    }
}

// MARK: - Edit Model Dialog

/// 编辑 profile 主模型 — 复用现有 `AddMainModelSheet` 与 `ModelConfigViewModel`。
///
/// 注意：`AddMainModelSheet` 在 init 时会从 `viewModel.model` 同步初始值到 `@State`，
/// 因此必须先异步加载配置，再创建 sheet；否则弹窗会显示空表单。
struct EditAgentModelDialog: View {
    let profile: AgentProfile

    @State private var viewModel: ModelConfigViewModel? = nil
    @State private var isLoading: Bool = true
    @State private var errorText: String = ""

    var body: some View {
        ZStack {
            if let vm = viewModel {
                AddMainModelSheet(viewModel: vm)
            }

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.9)
                    Text("加载模型配置中...")
                        .font(.system(size: 12))
                        .foregroundColor(AgentPalette.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AgentPalette.bgElevated.opacity(0.92))
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorText = ""
        DMLogger.log(
            "[EditAgentModelDialog] load START profileId=\(profile.id)",
            name: "AgentDialogs"
        )
        let vm = ModelConfigViewModel(profile: profile.id)
        await vm.load()
        DMLogger.log(
            "[EditAgentModelDialog] load DONE profileId=\(profile.id) " +
            "provider=\(vm.model.providerKey) model=\(vm.model.modelId) " +
            "apiKeyLen=\(vm.model.apiKey?.count ?? 0)",
            name: "AgentDialogs"
        )
        viewModel = vm
        isLoading = false
    }
}

// MARK: - Edit SOUL.md Dialog

/// 编辑 profile 的 SOUL.md（人格 / 系统提示词）。
struct EditAgentSoulDialog: View {
    @ObservedObject var viewModel: AgentViewModel
    let profile: AgentProfile
    @Environment(\.dismiss) private var dismiss

    @State private var content: String = ""
    @State private var isLoading: Bool = true
    @State private var errorText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AgentPalette.divider)

            ZStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SOUL.md 定义该 agent 的身份、语气与行为准则。保存后新会话生效。")
                        .font(.system(size: 11))
                        .foregroundColor(AgentPalette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $content)
                        .font(.system(size: 12))
                        .foregroundColor(AgentPalette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AgentPalette.bgPanel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AgentPalette.border, lineWidth: 0.5)
                        )

                    if !errorText.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.20))
                            Text(errorText)
                                .font(.system(size: 11.5))
                                .foregroundColor(AgentPalette.textPrimary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0.18, green: 0.13, blue: 0.06))
                        )
                    }
                }
                .padding(20)
                .disabled(isLoading || viewModel.isSubmitting)

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.9)
                        Text("读取 SOUL.md 中...")
                            .font(.system(size: 12))
                            .foregroundColor(AgentPalette.textMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AgentPalette.bgElevated.opacity(0.92))
                }
            }

            Divider().overlay(AgentPalette.divider)
            footer
        }
        .frame(width: 560, height: 480)
        .background(AgentPalette.bgElevated)
        .task { await loadSoul() }
        .onAppear {
            DMLogger.log(
                "[EditAgentSoulDialog] onAppear profileId=\(profile.id) contentLen=\(content.count)",
                name: "AgentDialogs"
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Text("\(AgentText.soulTitle) · \(profile.id)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AgentPalette.textMuted)
                    .padding(6)
                    .background(Circle().fill(AgentPalette.bgPanel))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(AgentText.cancel) { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AgentPalette.textMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)
            Button(action: { submit() }) {
                HStack(spacing: 5) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(AgentText.save)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(AgentPalette.inverseInk)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(viewModel.isSubmitting ? AgentPalette.textDisabled : AgentPalette.inverse)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func loadSoul() async {
        isLoading = true
        errorText = ""
        DMLogger.log(
            "[EditAgentSoulDialog] loadSoul START profileId=\(profile.id)",
            name: "AgentDialogs"
        )
        content = await viewModel.soulMd(for: profile.id)
        DMLogger.log(
            "[EditAgentSoulDialog] loadSoul DONE profileId=\(profile.id) contentLen=\(content.count)",
            name: "AgentDialogs"
        )
        isLoading = false
    }

    private func submit() {
        Task {
            let ok = await viewModel.saveSoulMd(for: profile.id, content: content)
            if ok { dismiss() }
            else {
                errorText = viewModel.model.errorMessage.isEmpty
                    ? "保存失败"
                    : viewModel.model.errorMessage
            }
        }
    }
}

// MARK: - Edit Skills Dialog

/// 编辑 profile 的技能：展示已安装技能并通过下拉框安装新技能。
struct EditAgentSkillsDialog: View {
    @ObservedObject var viewModel: AgentViewModel
    let profile: AgentProfile
    @Environment(\.dismiss) private var dismiss

    @State private var builtIn: [SkillCategoryGroup] = []
    @State private var available: [SkillCategoryGroup] = []
    @State private var isLoading: Bool = true
    @State private var selectedSkillId: String = ""
    @State private var errorText: String = ""
    @State private var operationSkillId: String? = nil

    /// 所有可选安装的技能（去重，按名称排序）。
    private var installableSkills: [SkillItem] {
        available
            .flatMap { $0.skills }
            .filter { !$0.isEnabled }
            .sorted { $0.name < $1.name }
    }

    /// 所有已启用的技能（内置 + 已安装可选）。
    private var enabledSkills: [SkillItem] {
        let builtInEnabled = builtIn.flatMap { $0.skills }.filter { $0.isEnabled }
        let availableEnabled = available.flatMap { $0.skills }.filter { $0.isEnabled }
        return (builtInEnabled + availableEnabled).sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AgentPalette.divider)

            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        hintText
                        addSkillSection
                        installedSkillsSection
                        if !errorText.isEmpty {
                            errorView(errorText)
                        }
                    }
                    .padding(20)
                }
                .disabled(isLoading || operationSkillId != nil)

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.9)
                        Text("加载技能列表中...")
                            .font(.system(size: 12))
                            .foregroundColor(AgentPalette.textMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AgentPalette.bgElevated.opacity(0.92))
                }
            }

            Divider().overlay(AgentPalette.divider)
            footer
        }
        .frame(width: 520, height: 620)
        .background(AgentPalette.bgElevated)
        .task { await load() }
        .onAppear {
            DMLogger.log(
                "[EditAgentSkillsDialog] onAppear profileId=\(profile.id) " +
                "builtIn=\(builtIn.count) available=\(available.count)",
                name: "AgentDialogs"
            )
        }
    }

    private var hintText: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundColor(AgentPalette.textMuted)
            Text("技能的更改在下一次会话时生效。内置技能默认启用；可选技能需要手动安装。")
                .font(.system(size: 11))
                .foregroundColor(AgentPalette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addSkillSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("安装技能")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(AgentPalette.textMuted)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                Picker("", selection: $selectedSkillId) {
                    Text("选择要安装的技能…").tag("")
                    ForEach(installableSkills) { skill in
                        Text("\(skill.name) (\(skill.category))").tag(skill.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AgentPalette.bgPanel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AgentPalette.border, lineWidth: 0.5)
                )

                Button(action: { installSelected() }) {
                    HStack(spacing: 4) {
                        if operationSkillId == selectedSkillId, !selectedSkillId.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.6)
                        }
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("安装")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(AgentPalette.inverseInk)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedSkillId.isEmpty || operationSkillId != nil
                                  ? AgentPalette.textDisabled : AgentPalette.inverse)
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedSkillId.isEmpty || operationSkillId != nil)
            }
        }
    }

    private var installedSkillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已启用技能")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(AgentPalette.textMuted)
                .textCase(.uppercase)

            if enabledSkills.isEmpty {
                Text("当前没有已启用的技能")
                    .font(.system(size: 12))
                    .foregroundColor(AgentPalette.textDisabled)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 6) {
                    ForEach(enabledSkills) { skill in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AgentPalette.textPrimary)
                                if !skill.description.isEmpty {
                                    Text(skill.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(AgentPalette.textMuted)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if skill.category.isEmpty == false, !isBuiltIn(skill) {
                                Button(action: { uninstall(skill) }) {
                                    HStack(spacing: 4) {
                                        if operationSkillId == skill.id {
                                            ProgressView()
                                                .controlSize(.small)
                                                .scaleEffect(0.6)
                                        }
                                        Image(systemName: "minus")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("卸载")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(Color(red: 0.95, green: 0.70, blue: 0.70))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color(red: 0.30, green: 0.10, blue: 0.10))
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(operationSkillId != nil)
                            } else {
                                Text("内置")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AgentPalette.textMuted)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(AgentPalette.bgPanel)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(AgentPalette.border, lineWidth: 0.5)
                                    )
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AgentPalette.bgPanel)
                        )
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Text("\(AgentText.skillsTitle) · \(profile.id)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AgentPalette.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AgentPalette.textMuted)
                    .padding(6)
                    .background(Circle().fill(AgentPalette.bgPanel))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(AgentText.cancel) { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AgentPalette.textMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)
            Button(action: { dismiss() }) {
                Text(AgentText.close)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AgentPalette.inverseInk)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AgentPalette.inverse)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func errorView(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.95, green: 0.65, blue: 0.20))
            Text(msg)
                .font(.system(size: 11.5))
                .foregroundColor(AgentPalette.textPrimary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.18, green: 0.13, blue: 0.06))
        )
    }

    private func isBuiltIn(_ skill: SkillItem) -> Bool {
        builtIn.flatMap { $0.skills }.contains(where: { $0.id == skill.id })
    }

    private func load() async {
        isLoading = true
        errorText = ""
        DMLogger.log(
            "[EditAgentSkillsDialog] load START profileId=\(profile.id)",
            name: "AgentDialogs"
        )
        let state = await viewModel.loadSkills(for: profile.id)
        builtIn = state.builtIn
        available = state.available
        selectedSkillId = ""
        DMLogger.log(
            "[EditAgentSkillsDialog] load DONE profileId=\(profile.id) " +
            "builtInGroups=\(state.builtIn.count) availableGroups=\(state.available.count) " +
            "enabledSkills=\(enabledSkills.count)",
            name: "AgentDialogs"
        )
        isLoading = false
    }

    private func installSelected() {
        guard !selectedSkillId.isEmpty else { return }
        guard let skill = installableSkills.first(where: { $0.id == selectedSkillId }) else { return }
        operationSkillId = skill.id
        errorText = ""
        Task {
            let ok = await viewModel.installSkill(
                for: profile.id,
                category: skill.category,
                skillId: skill.id
            )
            operationSkillId = nil
            if ok {
                await load()
            } else {
                errorText = viewModel.model.errorMessage.isEmpty
                    ? "安装失败"
                    : viewModel.model.errorMessage
            }
        }
    }

    private func uninstall(_ skill: SkillItem) {
        operationSkillId = skill.id
        errorText = ""
        Task {
            let ok = await viewModel.uninstallSkill(for: profile.id, skillId: skill.id)
            operationSkillId = nil
            if ok {
                await load()
            } else {
                errorText = viewModel.model.errorMessage.isEmpty
                    ? "卸载失败"
                    : viewModel.model.errorMessage
            }
        }
    }
}
