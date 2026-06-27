import SwiftUI
import AppKit
import Combine

// MARK: - Skill Item

/// 任务看板专用的轻量技能条目 — 用于新任务对话框中的技能选择。
struct TBSkillItem: Equatable, Identifiable, Hashable {
    let id: String
    let name: String
}

// MARK: - Toast

/// 轻量级提示条 — 对应 Flutter 端 SnackBar。
/// 在窗口底部短暂显示一条文本，无需用户交互，自动淡出。
enum TBToast {

    /// 全局单例 holder — 任何 View 都能通过它发送 toast。
    @MainActor
    final class Holder: ObservableObject {
        static let shared = Holder()
        @Published var message: String = ""
        @Published var visible: Bool = false
        private var hideTask: Task<Void, Never>?

        func show(_ text: String, duration: TimeInterval = 2.4) {
            self.message = text
            withAnimation(.easeInOut(duration: 0.18)) {
                self.visible = true
            }
            hideTask?.cancel()
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        self?.visible = false
                    }
                }
            }
        }
    }

    /// 触发一条 toast。
    @MainActor
    static func show(_ message: String) {
        Holder.shared.show(message)
    }
}

/// 在窗口底部居中显示当前 toast。
struct TBToastOverlay: View {
    @ObservedObject private var holder = TBToast.Holder.shared

    var body: some View {
        VStack {
            Spacer()
            if holder.visible, !holder.message.isEmpty {
                Text(holder.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TBPalette.inverseInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(TBPalette.inverse)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(TBPalette.border, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 4)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}

// MARK: - New Board Dialog

/// 新建看板对话框 — 对齐 Flutter `_NewBoardDialog`。
///
/// 字段:
/// - slug(只允许小写字母数字 + 连字符/下划线,以字母数字开头,1-64 字符)
/// - name(必填,展示名)
/// - description(可选)
/// - icon(单字符 emoji 或 SF Symbol)
/// - autoSwitch(创建后立即切换到新看板)
struct TBNewBoardDialog: View {
    @ObservedObject var viewModel: TaskBoardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var slug: String = ""
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var icon: String = ""
    @State private var autoSwitch: Bool = false
    @State private var slugError: String? = nil

    /// slug 校验:小写字母数字 + -_, 1-64 字符,字母数字开头
    private static let slugPattern = "^[a-z0-9][a-z0-9_-]{0,63}$"
    private var isValidSlug: Bool {
        let s = slug.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return false }
        return s.range(of: Self.slugPattern, options: .regularExpression) != nil
    }

    private var canSubmit: Bool {
        isValidSlug
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 常用 emoji 提示
    private let iconSuggestions = ["📋", "🚀", "🛠", "🧪", "📦", "🌐", "🔍", "🧠", "🐛", "✨"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(TBText.newBoard)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(TBPalette.textPrimary)
                Text("创建一个新的 Hermes 看板（slug 全小写，用于文件系统路径）")
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

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TBDialogSection(title: "基础信息") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                TBFieldLabel(label: "Slug", required: true)
                                TBTextInputField(
                                    text: $slug,
                                    placeholder: "例如: backend-q3",
                                    isMultiline: false
                                )
                                if let err = slugError {
                                    Text(err)
                                        .font(.system(size: 11))
                                        .foregroundColor(TBPalette.statusDanger)
                                } else {
                                    Text("仅小写字母数字 + 连字符/下划线,以字母数字开头")
                                        .font(.system(size: 11))
                                        .foregroundColor(TBPalette.textMuted)
                                }
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                TBFieldLabel(label: "名称", required: true)
                                TBTextInputField(
                                    text: $name,
                                    placeholder: "例如: 后端 Q3 迭代",
                                    isMultiline: false
                                )
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                TBFieldLabel(label: "描述", required: false)
                                TBTextInputField(
                                    text: $description,
                                    placeholder: "选填,简要说明看板用途",
                                    isMultiline: true
                                )
                            }
                        }
                    }

                    TBDialogSection(title: "外观") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                TBFieldLabel(label: "图标", required: false)
                                HStack(spacing: 6) {
                                    TBTextInputField(
                                        text: $icon,
                                        placeholder: "例如: 📋 或 rectangle.stack",
                                        isMultiline: false
                                    )
                                    .frame(maxWidth: 220)
                                    if !icon.isEmpty {
                                        Text(icon)
                                            .font(.system(size: 22))
                                            .frame(width: 36, height: 36)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(TBPalette.bgElevated)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(TBPalette.border, lineWidth: 1)
                                            )
                                    }
                                }
                                if !iconSuggestions.isEmpty {
                                    FlowLayout(spacing: 6, runSpacing: 6) {
                                        ForEach(iconSuggestions, id: \.self) { s in
                                            Button {
                                                icon = s
                                            } label: {
                                                Text(s)
                                                    .font(.system(size: 16))
                                                    .frame(width: 30, height: 28)
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
                    }

                    TBDialogSection(title: "高级") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $autoSwitch) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.right.circle")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(TBPalette.textMuted)
                                    Text("创建后立即切换到该看板")
                                        .font(.system(size: 12))
                                        .foregroundColor(TBPalette.textPrimary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 480)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)

            // Footer
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
        .frame(width: 520)
        .background(TBPalette.bgBase)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(TBPalette.border, lineWidth: 1)
        )
        .onChange(of: slug) { _, new in
            slugError = validateSlug(new)
        }
    }

    private func validateSlug(_ value: String) -> String? {
        let s = value.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if s.range(of: Self.slugPattern, options: .regularExpression) == nil {
            return "格式不合法:仅小写字母数字 + 连字符/下划线,以字母数字开头"
        }
        return nil
    }

    private func submit() {
        let trimmedSlug = slug.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedSlug.isEmpty, !trimmedName.isEmpty,
              isValidSlug else { return }
        Task {
            await viewModel.createBoard(
                slug: trimmedSlug,
                name: trimmedName,
                description: description,
                icon: icon,
                autoSwitch: autoSwitch
            )
            await MainActor.run { dismiss() }
        }
    }
}

// MARK: - Rename Board Dialog

/// 重命名看板对话框 — 极简单行输入。
struct TBRenameBoardDialog: View {
    let currentName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("重命名看板")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(TBPalette.textPrimary)
                Text("修改后立即同步到 Hermes CLI")
                    .font(.system(size: 12))
                    .foregroundColor(TBPalette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .background(TBPalette.bgBase)

            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                TBFieldLabel(label: "新名称", required: true)
                TBTextInputField(
                    text: $draft,
                    placeholder: "新名称",
                    isMultiline: false
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)

            HStack(spacing: 10) {
                Spacer()
                Button(TBText.cancel) { onCancel() }
                    .buttonStyle(TBStatusButtonStyle(color: TBPalette.textMuted))
                Button("保存") {
                    let trimmed = draft.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { onSave(trimmed) }
                }
                .buttonStyle(TBStatusButtonStyle(color: TBPalette.statusComplete))
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
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
        .onAppear {
            draft = currentName
        }
    }
}

// MARK: - Animated Count

/// 数字变化时的过渡动画(列头卡片数)。
struct TBAnimatedCount: View {
    let value: Int
    var font: Font = .system(size: 11, weight: .regular)
    var color: Color = TBPalette.textMuted

    var body: some View {
        Text("\(value)")
            .font(font)
            .foregroundColor(color)
            .contentTransition(.numericText(value: Double(value)))
            .animation(.easeInOut(duration: 0.22), value: value)
    }
}

// MARK: - Status Indicator

/// 状态圆点指示器(用于列头区分 active / empty)。
struct TBStatusDot: View {
    let color: Color
    var size: CGFloat = 6
    var pulse: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 1)
                    .scaleEffect(pulse ? 2.2 : 1.0)
                    .opacity(pulse ? 0 : 0.7)
                    .animation(
                        pulse
                            ? .easeOut(duration: 1.6).repeatForever(autoreverses: false)
                            : .default,
                        value: pulse
                    )
            )
    }
}

// MARK: - Keyboard Hint Chip

/// 键盘快捷键小标签 — 例如 `⌘N`。
struct TBKeyHint: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(TBPalette.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(TBPalette.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(TBPalette.border, lineWidth: 1)
            )
    }
}

// MARK: - Section Title

/// 分区小标题(大写、字母间距)— 用于详情弹窗中的"运行历史"等区块。
struct TBSectionTitle: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(TBPalette.textHeader)
                .textCase(.uppercase)
                .tracking(0.6)
            Rectangle()
                .fill(TBPalette.divider)
                .frame(height: 1)
            if let trailing = trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(TBPalette.textMuted)
            }
        }
    }
}

// MARK: - Empty Hint

/// 单元格内的"空"提示,带 muted 图标。
struct TBEmptyHint: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(TBPalette.textMuted)
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(TBPalette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }
}
