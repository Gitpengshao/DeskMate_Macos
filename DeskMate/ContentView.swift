import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var viewModel: PetViewModel

    var body: some View {
        PetImageView(viewModel: viewModel)
            .frame(width: viewModel.petSize.width, height: viewModel.petSize.height)
            .scaleEffect(x: viewModel.facingRight ? 1 : -1, y: 1)
            .background(Color.clear)
    }
}

struct PetImageView: NSViewRepresentable {
    @ObservedObject var viewModel: PetViewModel

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = false
        imageView.wantsLayer = true
        imageView.layer?.isOpaque = false
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== viewModel.currentFrame {
            nsView.image = viewModel.currentFrame
        }
    }
}
