import SwiftUI

// MARK: - Loading / Empty / Error

struct TBLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("加载中…")
                .font(.system(size: 13))
                .foregroundColor(TBPalette.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TBEmptyView: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundColor(TBPalette.textMuted.opacity(0.6))
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(TBPalette.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct TBErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(TBPalette.statusBlock)
        )
    }
}

// MARK: - Pills

struct TBPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.25), lineWidth: 1)
            )
    }
}

// MARK: - Button Style

struct TBStatusButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(configuration.isPressed ? 0.85 : 1.0))
            )
    }
}

// MARK: - Simplified Task Detail Popup

struct TBTaskDetailPopup: View {
    let task: TaskItem
    @ObservedObject var viewModel: TaskBoardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showBlockAlert = false
    @State private var blockReason = ""
    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .background(TBPalette.divider)
            content
            Divider()
                .background(TBPalette.divider)
            footer
        }
        .frame(width: 420)
        .background(TBPalette.bgBase)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(TBPalette.border, lineWidth: 1)
        )
        .alert("阻塞原因", isPresented: $showBlockAlert) {
            TextField("请输入阻塞原因", text: $blockReason)
            Button("取消", role: .cancel) { blockReason = "" }
            Button("阻塞", role: .destructive) {
                perform { await viewModel.blockTask(task.id, reason: blockReason) }
            }
        } message: {
            Text("该原因会同步到 Hermes Kanban。")
        }
        .disabled(isProcessing)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(TBPalette.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    TBPill(text: task.status.label, color: statusColor(task.status))
                    TBPill(text: task.priority, color: TBPalette.textMuted)
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(TBPalette.textMuted)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(TBPalette.inputBg)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(TBPalette.bgBase)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !task.body.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("描述")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TBPalette.textMuted)
                        Text(task.body)
                            .font(.system(size: 13))
                            .foregroundColor(TBPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                infoRow(label: "负责人", value: task.assignee)
                infoRow(label: "工作目录", value: task.workspace)
                infoRow(label: "Tenant", value: task.tenant)
                infoRow(label: "创建时间", value: TBFormatters.dateTime.string(from: task.createdAt))
            }
            .padding(20)
        }
        .frame(maxHeight: 320)
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TBPalette.textMuted)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13))
                .foregroundColor(TBPalette.textPrimary)
                .textSelection(.enabled)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            if task.status == .blocked {
                Button("解除阻塞") {
                    perform { await viewModel.unblockTask(task.id) }
                }
                .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusStart))
            } else {
                Button("阻塞") {
                    showBlockAlert = true
                }
                .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusBlock))
            }

            if task.status != .done && task.status != .archived {
                Button("完成") {
                    perform { await viewModel.completeTask(task.id) }
                }
                .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusComplete))
            }

            Button("删除") {
                perform { await viewModel.deleteTask(task.id) }
            }
            .buttonStyle(TBStatusButtonStyle(color: TBPalette.textMuted))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(TBPalette.bgBase)
    }

    private func perform(action: @escaping () async -> Void) {
        isProcessing = true
        Task {
            await action()
            await MainActor.run {
                isProcessing = false
                dismiss()
            }
        }
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .todo:     return Color(red: 0.231, green: 0.510, blue: 0.965)
        case .ready:    return Color(red: 0.50, green: 0.35, blue: 0.95)
        case .running:  return Color(red: 0.133, green: 0.773, blue: 0.369)
        case .blocked:  return Color(red: 0.961, green: 0.620, blue: 0.043)
        case .done:     return Color(red: 0.420, green: 0.420, blue: 0.420)
        case .triage, .archived: return Color.gray
        }
    }
}

// MARK: - Formatters

private enum TBFormatters {
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
