import SwiftUI

// MARK: - GCPalette (复用 MCPalette 色值，保持黑白主题一致)

/// 网关配置页色板 — 与 `MCPalette` / `Palette` 保持一致。
enum GCPalette {
    static let bgBase       = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let bgPanel      = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let bgElevated   = Color(red: 0.078, green: 0.078, blue: 0.078)
    static let bgHover      = Color(red: 0.110, green: 0.110, blue: 0.110)
    static let border       = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let borderStrong = Color(red: 0.260, green: 0.260, blue: 0.260)
    static let textPrimary  = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let textSecond   = Color(red: 0.640, green: 0.640, blue: 0.640)
    static let textTertiary = Color(red: 0.420, green: 0.420, blue: 0.420)
    static let accent       = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let accentInk    = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let good         = Color(red: 0.30, green: 0.85, blue: 0.40)
    static let bad          = Color(red: 0.95, green: 0.30, blue: 0.30)
}

// MARK: - ConfigCard

/// 带标题的分组容器卡片。
struct ConfigCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(GCPalette.textPrimary)
                    .tracking(0.2)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(GCPalette.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            content
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(GCPalette.bgPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GCPalette.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - ConfigRow

/// label + 控件的对齐行。label 固定宽度，控件占据剩余空间。
struct ConfigRow<Control: View>: View {
    let label: String
    let hint: String?
    let control: Control

    init(label: String, hint: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.hint = hint
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(GCPalette.textSecond)
                if let hint = hint {
                    Text(hint)
                        .font(.system(size: 10.5))
                        .foregroundColor(GCPalette.textTertiary)
                }
            }
            .frame(width: 130, alignment: .leading)

            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - PrimaryButton / SecondaryButton

struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isDestructive: Bool
    let action: () -> Void

    init(title: String, icon: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isDestructive ? GCPalette.bad : GCPalette.accentInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isDestructive ? Color.clear : GCPalette.accent)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isDestructive ? GCPalette.bad : GCPalette.accent, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(GCPalette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(GCPalette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(GCPalette.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GCTextField / GCSecureField / GCPicker

struct GCTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 12.5))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(GCPalette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(GCPalette.border, lineWidth: 1)
                    )
            )
            .foregroundColor(GCPalette.textPrimary)
    }
}

struct GCSecureField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SecureField(placeholder, text: $text)
            .font(.system(size: 12.5))
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(GCPalette.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(GCPalette.border, lineWidth: 1)
                    )
            )
            .foregroundColor(GCPalette.textPrimary)
    }
}

struct GCPicker: View {
    let label: String
    let options: [(value: String, label: String)]
    @Binding var selection: String

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options, id: \.value) { opt in
                Text(opt.label).tag(opt.value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.system(size: 12.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(GCPalette.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(GCPalette.border, lineWidth: 1)
                )
        )
        .foregroundColor(GCPalette.textPrimary)
    }
}

// MARK: - StatusDot

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.5), radius: 2)
    }
}

// MARK: - InteractiveConsoleSheet

/// 交互式命令输出 + stdin 输入的 sheet。
/// 用于 `hermes gateway setup` 扫码、依赖安装等场景。
struct InteractiveConsoleSheet: View {
    @ObservedObject var viewModel: GatewayConfigViewModel
    @State private var inputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(viewModel.interactiveTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GCPalette.textPrimary)
                Spacer()
                if let code = viewModel.lastExitCode {
                    Text("退出码 \(code)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(code == 0 ? GCPalette.good : GCPalette.bad)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(GCPalette.bgElevated)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(GCPalette.bgPanel)
            .overlay(
                Rectangle().fill(GCPalette.border).frame(height: 1),
                alignment: .bottom
            )

            // 输出区
            ScrollViewReader { proxy in
                ScrollView {
                    Text(viewModel.interactiveOutput.isEmpty ? "（等待输出...）" : viewModel.interactiveOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(GCPalette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("output-end")
                        .textSelection(.enabled)
                }
                .background(Color.black)
                .onChange(of: viewModel.interactiveOutput) { _ in
                    withAnimation {
                        proxy.scrollTo("output-end", anchor: .bottom)
                    }
                }
            }

            // 输入栏（仅交互式 setup 进程运行时显示；安装类命令无 stdin）
            if viewModel.lastExitCode == nil && viewModel.interactiveTitle.contains("setup") {
                HStack(spacing: 8) {
                    GCTextField(placeholder: "输入选择或凭据后回车...", text: $inputText)
                        .onSubmit {
                            sendCurrent()
                        }
                    PrimaryButton(title: "发送", icon: "paperplane") {
                        sendCurrent()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GCPalette.bgPanel)
                .overlay(
                    Rectangle().fill(GCPalette.border).frame(height: 1),
                    alignment: .top
                )
            }

            // 底部按钮栏
            HStack(spacing: 10) {
                if viewModel.lastExitCode == nil {
                    SecondaryButton(title: "终止进程", icon: "xmark.circle") {
                        viewModel.cancelInteractive()
                    }
                }
                Spacer()
                SecondaryButton(title: viewModel.lastExitCode == nil ? "在 Terminal 打开" : "刷新配置", icon: viewModel.lastExitCode == nil ? "terminal" : "arrow.clockwise") {
                    if viewModel.lastExitCode == nil {
                        viewModel.openSetupInTerminal()
                    } else {
                        viewModel.loadAll()
                    }
                }
                PrimaryButton(title: "关闭", icon: nil) {
                    viewModel.dismissInteractive()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(GCPalette.bgPanel)
            .overlay(
                Rectangle().fill(GCPalette.border).frame(height: 1),
                alignment: .top
            )
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(Color.black)
    }

    private func sendCurrent() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.sendInput(text)
        inputText = ""
    }
}
