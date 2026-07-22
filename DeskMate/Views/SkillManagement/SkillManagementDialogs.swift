import SwiftUI

// MARK: - Create Skill Dialog

/// 创建自定义技能弹窗 — 写入 `~/.hermes/skills/<category>/<name>/SKILL.md`。
struct SMCreateSkillDialog: View {
    @ObservedObject var viewModel: SkillManagementViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var category: String = ""
    @State private var content: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(SMPalette.border)
            ScrollView {
                contentForm
                    .padding(20)
            }
            .disabled(isSubmitting)
            Divider().overlay(SMPalette.border)
            footer
        }
        .frame(width: 540, height: 520)
        .background(SMPalette.bgBase)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.square")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(SMPalette.textPrimary)
            Text("创建技能")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(SMPalette.textPrimary)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SMPalette.textMuted)
                    .padding(6)
                    .background(Circle().fill(SMPalette.bgElevated))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Form

    private var contentForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            formField("技能名称", text: $name, placeholder: "my-skill")
            formField("分类", text: $category, placeholder: "productivity")
            formField("描述", text: $description, placeholder: "简要说明该技能的用途")

            VStack(alignment: .leading, spacing: 6) {
                Text("SKILL.md 正文")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(SMPalette.textMuted)
                    .textCase(.uppercase)
                TextEditor(text: $content)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .background(SMPalette.bgElevated)
                    .foregroundColor(SMPalette.textPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SMPalette.border, lineWidth: 0.56)
                    )
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundColor(SMPalette.statusError)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func formField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(SMPalette.textMuted)
                .textCase(.uppercase)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(SMPalette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(SMPalette.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(SMPalette.border, lineWidth: 0.56)
                )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("取消") { dismiss() }
                .buttonStyle(SMSecondaryButtonStyle())
            Button("创建") { submit() }
                .buttonStyle(SMPrimaryButtonStyle(isLoading: isSubmitting))
                .disabled(isSubmitting || !isValid)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard isValid else { return }
        isSubmitting = true
        errorText = ""
        Task {
            let ok = await viewModel.createSkill(
                name: name,
                description: description,
                category: category,
                content: content
            )
            isSubmitting = false
            if ok {
                dismiss()
            } else {
                errorText = viewModel.model.errorMessage ?? "创建失败"
            }
        }
    }
}

// MARK: - Button Styles

private struct SMPrimaryButtonStyle: ButtonStyle {
    let isLoading: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)
            }
            configuration.label
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(SMPalette.inverseInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(SMPalette.inverse)
        )
    }
}

private struct SMSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(SMPalette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(SMPalette.border, lineWidth: 0.56)
            )
    }
}
