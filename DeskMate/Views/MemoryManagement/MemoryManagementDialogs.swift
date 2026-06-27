import SwiftUI

// MARK: - Add / Edit Entry Sheet

/// 新增 / 编辑记忆条目对话框。
/// 对齐 Flutter `_showAddMemoryDialog` / `_showEditMemoryDialog` 行为。
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
        return target == .memory ? MMText.addEntry : MMText.newPersona
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MMPalette.border)
            content
            Divider().background(MMPalette.border)
            footer
        }
        .frame(width: 480, height: 360)
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
            Image(systemName: target == .memory ? "brain.head.profile" : "person.crop.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MMPalette.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MMPalette.textPrimary)
                Text(target == .memory ? "MEMORY.md" : "USER.md")
                    .font(.system(size: 11))
                    .foregroundColor(MMPalette.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(MMText.addPlaceholder)
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
                if target == .memory {
                    await viewModel.editMemoryEntry(entry.id, newContent: trimmed)
                } else {
                    await viewModel.editUserProfileEntry(entry.id, newContent: trimmed)
                }
            } else {
                if target == .memory {
                    await viewModel.addMemoryEntry(trimmed)
                } else {
                    await viewModel.addUserProfileEntry(trimmed)
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
                Text(entry.target == .memory ? "MEMORY.md" : "USER.md")
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
            if entry.target == .memory {
                await viewModel.deleteMemoryEntry(entry.id)
            } else {
                await viewModel.deleteUserProfileEntry(entry.id)
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

// MARK: - Python Picker

/// Python 解释器选择器：列出扫描到的候选，点击即可切换。
struct MMPythonPickerSheet: View {
    @ObservedObject var viewModel: MemoryManagementViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MMPalette.border)
            content
            Divider().background(MMPalette.border)
            footer
        }
        .frame(width: 520, height: 460)
        .background(MMPalette.bgPanel)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(MMText.pythonPickerTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MMPalette.textPrimary)
            Text(MMText.pythonPickerSubtitle)
                .font(.system(size: 11))
                .foregroundColor(MMPalette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.model.isScanningPython {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)
                Text(MMText.pythonPickerScanning)
                    .font(.system(size: 11))
                    .foregroundColor(MMPalette.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.model.pythonCandidates.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22))
                    .foregroundColor(MMPalette.statusError)
                Text(MMText.pythonPickerEmpty)
                    .font(.system(size: 12))
                    .foregroundColor(MMPalette.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(viewModel.model.pythonCandidates) { candidate in
                        candidateRow(candidate)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    private func candidateRow(_ candidate: PythonCandidate) -> some View {
        let isCurrent = candidate.path == viewModel.model.pythonPath
        return Button {
            viewModel.selectPythonCandidate(candidate)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(
                            isCurrent ? MMPalette.textPrimary : MMPalette.border,
                            lineWidth: 1.2
                        )
                        .frame(width: 14, height: 14)
                    if isCurrent {
                        Circle()
                            .fill(MMPalette.textPrimary)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(candidate.version)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MMPalette.textPrimary)
                        if candidate.isSystemPython {
                            Text(MMText.pythonPickerSystem)
                                .font(.system(size: 10))
                                .foregroundColor(MMPalette.statusInstalling)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .overlay(
                                    Capsule().stroke(MMPalette.statusInstalling, lineWidth: 0.8)
                                )
                        }
                        if isCurrent {
                            Text(MMText.pythonPickerCurrent)
                                .font(.system(size: 10))
                                .foregroundColor(MMPalette.statusRunning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .overlay(
                                    Capsule().stroke(MMPalette.statusRunning, lineWidth: 0.8)
                                )
                        }
                    }
                    Text(candidate.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(MMPalette.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("pip \(candidate.pipVersion)")
                        .font(.system(size: 10))
                        .foregroundColor(MMPalette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? MMPalette.bgElevated : MMPalette.bgBase)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isCurrent ? MMPalette.textPrimary.opacity(0.4) : MMPalette.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(MMText.providerPythonRescan) {
                Task { await viewModel.rescanPythonCandidates() }
            }
            .buttonStyle(MMSecondaryButtonStyle())

            Spacer()

            Button(MMText.pythonPickerClear) {
                viewModel.clearPythonOverride()
                dismiss()
            }
            .buttonStyle(MMSecondaryButtonStyle())

            Button(MMText.pythonPickerClose) {
                viewModel.dismissPythonPicker()
            }
            .buttonStyle(MMSecondaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
