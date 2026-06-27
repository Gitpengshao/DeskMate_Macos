import SwiftUI
import AppKit

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
