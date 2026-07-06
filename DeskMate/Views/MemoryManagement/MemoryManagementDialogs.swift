import SwiftUI

// MARK: - Add / Edit Entry Sheet

/// 新增 / 编辑记忆条目对话框。
struct MMEntryEditorSheet: View {
    @ObservedObject var viewModel: MemoryManagementViewModel
    let target: MemoryTarget
    /// nil = 新增；非 nil = 编辑该条目。
    let editingEntry: MemoryEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var isSubmitting: Bool = false

    private var isEditing: Bool { editingEntry != nil }
    private var titleText: String {
        if isEditing { return MMText.editEntry }
        return target == .user ? MMText.newPersona : MMText.addEntry
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MMPalette.border)
            content
            Divider().background(MMPalette.border)
            footer
        }
        .frame(width: 480, height: target == .soul ? 520 : 360)
        .background(MMPalette.bgBase)
        .preferredColorScheme(.dark)
        .onAppear {
            if let entry = editingEntry {
                text = entry.content
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: headerIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MMPalette.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MMPalette.textPrimary)
                Text(fileName)
                    .font(.system(size: 11))
                    .foregroundColor(MMPalette.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var headerIcon: String {
        switch target {
        case .memory: return "brain.head.profile"
        case .user:   return "person.crop.circle"
        case .soul:   return "sparkles"
        }
    }

    private var fileName: String {
        switch target {
        case .memory: return "MEMORY.md"
        case .user:   return "USER.md"
        case .soul:   return "SOUL.md"
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(placeholder)
                .font(.system(size: 11))
                .foregroundColor(MMPalette.textTertiary)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(MMPalette.bgInput)
                .foregroundColor(MMPalette.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MMPalette.border, lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
    }

    private var placeholder: String {
        switch target {
        case .memory:
            return "例如：- 使用 § 分隔条目\n- 每条记忆独立成段"
        case .user:
            return "例如：- 用户偏好使用中文交流\n- 喜欢简洁的回答"
        case .soul:
            return "编辑 Agent 的灵魂画像 / 性格设定。SOUL.md 为单文件，不支持新增或删除条目。"
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button(MMText.cancel) { dismiss() }
                .buttonStyle(MMSecondaryButtonStyle())
            Button(MMText.confirm) { submit() }
                .buttonStyle(MMPrimaryButtonStyle(isLoading: isSubmitting))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        isSubmitting = true
        Task {
            if let entry = editingEntry {
                switch target {
                case .memory:
                    await viewModel.editMemoryEntry(entry.id, newContent: trimmed)
                case .user:
                    await viewModel.editUserProfileEntry(entry.id, newContent: trimmed)
                case .soul:
                    await viewModel.editSoulProfileEntry(entry.id, newContent: trimmed)
                }
            } else {
                switch target {
                case .memory:
                    await viewModel.addMemoryEntry(trimmed)
                case .user:
                    await viewModel.addUserProfileEntry(trimmed)
                case .soul:
                    // SOUL.md 不支持新增条目。
                    break
                }
            }
            isSubmitting = false
            dismiss()
        }
    }
}

// MARK: - Delete Confirmation

/// 删除确认对话框。
struct MMDeleteConfirmDialog: View {
    @ObservedObject var viewModel: MemoryManagementViewModel
    let entry: MemoryEntry

    @Environment(\.dismiss) private var dismiss
    @State private var isDeleting: Bool = false

    private var preview: String {
        if entry.content.count > 40 {
            return String(entry.content.prefix(40)) + "..."
        }
        return entry.content
    }

    private var fileName: String {
        switch entry.target {
        case .memory: return "MEMORY.md"
        case .user:   return "USER.md"
        case .soul:   return "SOUL.md"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MMPalette.statusError)
                Text(MMText.deletePersonaTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MMPalette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Divider().background(MMPalette.border)
            VStack(alignment: .leading, spacing: 10) {
                Text(MMText.deletePersonaConfirm(preview))
                    .font(.system(size: 13))
                    .foregroundColor(MMPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(fileName)
                    .font(.system(size: 11))
                    .foregroundColor(MMPalette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            Divider().background(MMPalette.border)
            HStack(spacing: 10) {
                Spacer()
                Button(MMText.cancel) { dismiss() }
                    .buttonStyle(MMSecondaryButtonStyle())
                Button(MMText.delete) { confirm() }
                    .buttonStyle(MMDestructiveButtonStyle(isLoading: isDeleting))
                    .disabled(isDeleting)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 220)
        .background(MMPalette.bgBase)
        .preferredColorScheme(.dark)
    }

    private func confirm() {
        isDeleting = true
        Task {
            switch entry.target {
            case .memory:
                await viewModel.deleteMemoryEntry(entry.id)
            case .user:
                await viewModel.deleteUserProfileEntry(entry.id)
            case .soul:
                // SOUL.md 不支持删除。
                break
            }
            isDeleting = false
            dismiss()
        }
    }
}

// MARK: - Button Styles (Monochrome)

struct MMPrimaryButtonStyle: ButtonStyle {
    var isLoading: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .colorScheme(.dark)
                    .scaleEffect(0.7)
            }
            configuration.label
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(MMPalette.inverseInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MMPalette.inverse.opacity(configuration.isPressed ? 0.7 : 1.0))
        )
        .contentShape(Rectangle())
    }
}

struct MMSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(MMPalette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(MMPalette.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MMPalette.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

struct MMDestructiveButtonStyle: ButtonStyle {
    var isLoading: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .colorScheme(.dark)
                    .scaleEffect(0.7)
            }
            configuration.label
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(MMPalette.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MMPalette.statusError.opacity(configuration.isPressed ? 0.6 : 0.85))
        )
        .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
