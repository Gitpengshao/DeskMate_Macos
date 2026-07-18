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

// MARK: - Task Detail Popup

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
        .frame(width: 460)
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(TBPalette.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    TBPill(text: task.status.label, color: statusColor(task.status))
                    if !task.priority.isEmpty {
                        TBPill(text: task.priority, color: TBPalette.textMuted)
                    }
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Button {
                    Task { await viewModel.loadTaskDetail(task.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TBPalette.textMuted)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(TBPalette.inputBg)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(TBPalette.textMuted)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(TBPalette.inputBg)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(TBPalette.bgBase)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 基础元数据
                VStack(alignment: .leading, spacing: 10) {
                    infoRow(label: "负责人", value: task.assignee)
                    infoRow(label: "工作区", value: task.workspace)
                    infoRow(label: "创建者", value: task.creator)
                    infoRow(label: "Tenant", value: task.tenant)
                    infoRow(label: "创建时间", value: TBFormatters.dateTime.string(from: task.createdAt))
                    infoRow(label: "更新时间", value: TBFormatters.dateTime.string(from: task.updatedAt))
                }

                if !task.body.isEmpty {
                    section(title: "描述") {
                        Text(task.body)
                            .font(.system(size: 13))
                            .foregroundColor(TBPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // 延误原因 / 诊断日志
                if !task.diagnosticLogs.isEmpty {
                    section(title: "延误原因 / 诊断日志") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(task.diagnosticLogs.sorted(by: { $0.createdAt > $1.createdAt }).prefix(5)) { log in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(TBPalette.statusBlock)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        if !log.reason.isEmpty {
                                            Text(log.reason)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(TBPalette.textPrimary)
                                        }
                                        if !log.detail.isEmpty {
                                            Text(log.detail)
                                                .font(.system(size: 11))
                                                .foregroundColor(TBPalette.textMuted)
                                        }
                                        Text(TBFormatters.dateTime.string(from: log.createdAt))
                                            .font(.system(size: 10))
                                            .foregroundColor(TBPalette.textMuted)
                                    }
                                }
                            }
                        }
                    }
                }

                // 评论列表
                section(title: "评论") {
                    if task.comments.isEmpty {
                        TBEmptyHint(text: "暂无评论")
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(task.comments.sorted(by: { $0.createdAt < $1.createdAt })) { comment in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(comment.author)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(TBPalette.textPrimary)
                                        Text(TBFormatters.dateTime.string(from: comment.createdAt))
                                            .font(.system(size: 10))
                                            .foregroundColor(TBPalette.textMuted)
                                    }
                                    Text(comment.body)
                                        .font(.system(size: 12))
                                        .foregroundColor(TBPalette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(TBPalette.inputBg)
                                )
                            }
                        }
                    }
                }

                // 事件列表
                section(title: "事件") {
                    if task.events.isEmpty {
                        TBEmptyHint(text: "暂无事件")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(task.events.sorted(by: { $0.createdAt > $1.createdAt })) { event in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(TBPalette.textMuted)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(eventText(event))
                                            .font(.system(size: 12))
                                            .foregroundColor(TBPalette.textPrimary)
                                        Text(TBFormatters.dateTime.string(from: event.createdAt))
                                            .font(.system(size: 10))
                                            .foregroundColor(TBPalette.textMuted)
                                    }
                                }
                            }
                        }
                    }
                }

                // 工作日志
                section(title: "工作日志") {
                    if task.runHistory.isEmpty {
                        TBEmptyHint(text: "暂无运行记录")
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(task.runHistory.sorted(by: { $0.started > $1.started }).prefix(5)) { run in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        TBPill(text: run.outcome, color: runColor(run.outcome))
                                        Text(run.profile)
                                            .font(.system(size: 11))
                                            .foregroundColor(TBPalette.textMuted)
                                        Spacer()
                                        Text(TBFormatters.dateTime.string(from: run.started))
                                            .font(.system(size: 10))
                                            .foregroundColor(TBPalette.textMuted)
                                    }
                                    if !run.error.isEmpty {
                                        Text(run.error)
                                            .font(.system(size: 11))
                                            .foregroundColor(TBPalette.statusBlock)
                                    }
                                    if !run.summary.isEmpty {
                                        Text(run.summary)
                                            .font(.system(size: 11))
                                            .foregroundColor(TBPalette.textMuted)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(TBPalette.inputBg)
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(maxHeight: 420)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TBSectionTitle(text: title)
            content()
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TBPalette.textMuted)
                .frame(width: 56, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 13))
                .foregroundColor(TBPalette.textPrimary)
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer()
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

            Button("归档") {
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

    private func eventText(_ event: TaskEvent) -> String {
        var text = event.type
        if !event.actor.isEmpty && event.actor != "system" {
            text += " · \(event.actor)"
        }
        if !event.note.isEmpty {
            text += "：\(event.note)"
        }
        return text
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

    private func runColor(_ outcome: String) -> Color {
        switch outcome.lowercased() {
        case "completed": return TBPalette.statusComplete
        case "gave_up", "spawn_failed", "timed_out", "failed": return TBPalette.statusDanger
        default: return TBPalette.statusBlock
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
