import SwiftUI
import AppKit

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

            // 输出区 + 二维码
            HStack(spacing: 0) {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let url = detectedURL {
                    Divider().background(GCPalette.border)

                    VStack(spacing: 14) {
                        if let qrImage = qrCodeImage(for: url) {
                            Image(nsImage: qrImage)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 200, height: 200)
                                .background(Color.white)
                                .cornerRadius(8)
                        }

                        Text("使用微信扫码")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(GCPalette.textPrimary)

                        Text(url)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(GCPalette.textTertiary)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 8) {
                            SecondaryButton(title: "复制链接", icon: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                            }

                            if let linkURL = URL(string: url) {
                                SecondaryButton(title: "打开链接", icon: "safari") {
                                    NSWorkspace.shared.open(linkURL)
                                }
                            }
                        }
                    }
                    .frame(width: 260)
                    .padding(20)
                    .background(GCPalette.bgPanel)
                }
            }

            // 输入栏（仅交互式 setup 进程运行时显示；安装类命令无 stdin）
            if viewModel.lastExitCode == nil && viewModel.interactiveTitle.contains("setup") {
                HStack(spacing: 8) {
                    TextField("输入选择或凭据后回车...", text: $inputText)
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
                if viewModel.lastExitCode == nil {
                    SecondaryButton(title: "在 Terminal 打开", icon: "terminal") {
                        viewModel.openSetupInTerminal()
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
        .frame(width: 960, height: 620)
        .background(Color.black)
    }

    private func sendCurrent() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.sendInput(text)
        inputText = ""
    }

    // MARK: - QR Code detection & rendering

    /// 从控制台输出中提取最可能是登录二维码的 URL。
    private var detectedURL: String? {
        let text = viewModel.interactiveOutput
        guard let regex = try? NSRegularExpression(pattern: "https?://[A-Za-z0-9\\-\\._~:/?#\\[\\]@!$&'()*+,;=%]+", options: []) else {
            return nil
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        // 优先匹配微信/飞书等登录二维码链接
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let url = String(text[range]).trimmingCharacters(in: .punctuationCharacters)
            let lowercased = url.lowercased()
            if lowercased.contains("liteapp.weixin.qq.com")
                || lowercased.contains("wx.qq.com")
                || lowercased.contains("qr")
                || lowercased.contains("login") {
                return url
            }
        }

        // 兜底：返回第一个 URL
        if let first = matches.first,
           let range = Range(first.range, in: text) {
            return String(text[range]).trimmingCharacters(in: .punctuationCharacters)
        }
        return nil
    }

    /// 用 Core Image 的 CIQRCodeGenerator 生成二维码 NSImage。
    private func qrCodeImage(for string: String) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        let scale: CGFloat = 12
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let size = NSSize(width: scaled.extent.width, height: scaled.extent.height)

        let rep = NSCIImageRep(ciImage: scaled)
        rep.size = size
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
