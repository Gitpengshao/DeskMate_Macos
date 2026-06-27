import SwiftUI
import WebKit

/// WKWebView 的 SwiftUI 包装。
///
/// 用于在 DeskMate 进程内加载 OpenViking 本地服务页面（默认 `http://localhost:1933`）。
struct MMWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}

/// OpenViking Provider WebView 窗口。
///
/// 在新进程中以独立窗口加载 OpenViking 服务地址。
/// 主题与记忆管理页一致：纯黑底 + 灰阶边框。
struct MMWebViewWindow: View {
    let urlString: String
    let onClose: () -> Void

    @State private var isHoveringClose: Bool = false

    private var url: URL? { URL(string: urlString) }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().background(MMPalette.border)
            content
        }
        .background(MMPalette.bgBase)
        .preferredColorScheme(.dark)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MMPalette.textPrimary)
            Text("OpenViking")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MMPalette.textPrimary)
            Text(urlString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(MMPalette.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MMPalette.textMuted)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHoveringClose ? MMPalette.bgHover : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MMPalette.bgElevated)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let url {
            MMWebView(url: url)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(MMPalette.statusError)
                Text("无效的 URL")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MMPalette.textPrimary)
                Text(urlString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(MMPalette.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
