import SwiftUI
import AppKit

struct PetImageView: NSViewRepresentable {
    @ObservedObject var viewModel: PetViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = false
        imageView.wantsLayer = true
        imageView.layer?.isOpaque = false
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        let baseImage = viewModel.currentFrame
        let facingRight = viewModel.facingRight

        // 仅在帧或方向变化时更新
        if context.coordinator.lastFrame !== baseImage || context.coordinator.lastFacingRight != facingRight {
            context.coordinator.lastFrame = baseImage
            context.coordinator.lastFacingRight = facingRight

            if facingRight {
                nsView.image = baseImage
            } else if let base = baseImage {
                // 使用缓存的翻转图像，避免每帧重新生成
                let key = ObjectIdentifier(base)
                if let cached = context.coordinator.flippedCache[key] {
                    nsView.image = cached
                } else {
                    let flipped = Self.flipImageHorizontal(base)
                    context.coordinator.flippedCache[key] = flipped
                    nsView.image = flipped
                }
            }
        }
    }

    /// 水平翻转 NSImage
    private static func flipImageHorizontal(_ image: NSImage) -> NSImage {
        let flipped = NSImage(size: image.size)
        flipped.lockFocus()
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: image.size.width, yBy: 0)
        transform.scaleX(by: -1, yBy: 1)
        transform.concat()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        flipped.unlockFocus()
        return flipped
    }

    // MARK: - Coordinator

    final class Coordinator {
        var lastFrame: NSImage?
        var lastFacingRight: Bool?
        var flippedCache: [ObjectIdentifier: NSImage] = [:]
    }
}
