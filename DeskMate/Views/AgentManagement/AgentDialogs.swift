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
                    if let err = errorText.isEmpty ? nil : errorText {
                        errorView(err)
                    }
                }
                .padding(20)
            }

            Divider().overlay(AgentPalette.divider)
            footer
        }
        .frame(width: 520, height: 540)
        .background(AgentPalette.bgElevated)
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

            Button(AgentText.create) { submit() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AgentPalette.inverseInk)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(profileName.isEmpty ? AgentPalette.textDisabled : AgentPalette.inverse)
                )
                .disabled(profileName.isEmpty)
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
                cloneFrom: selectedMode == .cloneFrom ? cloneFrom : nil
            )
            // 关闭对话框
            if viewModel.model.errorMessage.isEmpty {
                dismiss()
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
            Button(AgentText.save) { submit() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AgentPalette.inverseInk)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(newName.isEmpty ? AgentPalette.textDisabled : AgentPalette.inverse)
                )
                .disabled(newName.isEmpty)
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
            Button(AgentText.deleteProfile) { submit() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(confirmText == profile.id
                              ? Color(red: 0.78, green: 0.20, blue: 0.20)
                              : AgentPalette.textDisabled)
                )
                .disabled(confirmText != profile.id)
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
            Button(AgentText.save) { submit() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AgentPalette.inverseInk)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AgentPalette.inverse)
                )
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
