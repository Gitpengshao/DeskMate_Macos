import SwiftUI
import AppKit

struct PetImageView: View {
    @ObservedObject var viewModel: PetViewModel

    var body: some View {
        let bubbleHeight = viewModel.isListeningBubbleVisible ? viewModel.listeningBubbleHeight : 0
        let contentWidth = viewModel.petSize.width
        let contentHeight = viewModel.petSize.height + bubbleHeight

        ZStack {
            if let frame = viewModel.currentFrame {
                Image(nsImage: frame)
                    .resizable()
                    .scaleEffect(x: viewModel.facingRight ? 1 : -1, y: 1)
                    .frame(width: viewModel.petSize.width, height: viewModel.petSize.height)
                    .position(x: contentWidth / 2, y: bubbleHeight + viewModel.petSize.height / 2)
            }

            if viewModel.isListeningBubbleVisible {
                ListeningBubble(text: viewModel.listeningTranscript)
                    .frame(width: max(contentWidth - 12, 0), height: viewModel.listeningBubbleHeight)
                    .position(x: contentWidth / 2, y: bubbleHeight / 2)
            }
        }
        .frame(width: contentWidth, height: contentHeight)
    }
}

// MARK: - 聆听提示气泡

private struct ListeningBubble: View {
    let text: String

    @State private var breathScale: CGFloat = 1.0

    private var displayText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "主人我正在听，你请说"
            : text
    }

    private var isSpeaking: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(
                SpeechBubbleShape()
                    .fill(Color.black.opacity(0.92))
            )
            .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
            .scaleEffect(breathScale)
            .onAppear {
                updateBreathing()
            }
            .onChange(of: text) { _ in
                updateBreathing()
            }
    }

    private func updateBreathing() {
        if isSpeaking {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                breathScale = 1.06
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                breathScale = 1.0
            }
        }
    }
}

private struct SpeechBubbleShape: Shape {
    let cornerRadius: CGFloat = 10
    let tailWidth: CGFloat = 12
    let tailHeight: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let bubbleHeight = rect.height - tailHeight
        let w = rect.width
        let h = bubbleHeight
        let r = cornerRadius
        let tw = tailWidth
        let th = tailHeight
        let cx = rect.midX

        var path = Path()

        // 左上角
        path.move(to: CGPoint(x: 0, y: r))
        path.addLine(to: CGPoint(x: 0, y: h - r))
        path.addQuadCurve(to: CGPoint(x: r, y: h), control: CGPoint(x: 0, y: h))

        // 底边（带三角缺口）
        path.addLine(to: CGPoint(x: cx - tw / 2, y: h))
        path.addLine(to: CGPoint(x: cx, y: h + th))
        path.addLine(to: CGPoint(x: cx + tw / 2, y: h))
        path.addLine(to: CGPoint(x: w - r, y: h))
        path.addQuadCurve(to: CGPoint(x: w, y: h - r), control: CGPoint(x: w, y: h))

        // 右侧
        path.addLine(to: CGPoint(x: w, y: r))
        path.addQuadCurve(to: CGPoint(x: w - r, y: 0), control: CGPoint(x: w, y: 0))

        // 顶边
        path.addLine(to: CGPoint(x: r, y: 0))
        path.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: 0, y: 0))

        path.closeSubpath()
        return path
    }
}
