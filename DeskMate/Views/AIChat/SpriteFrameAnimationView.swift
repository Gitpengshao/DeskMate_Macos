import SwiftUI
import AppKit

/// 精灵图帧动画视图 — SwiftUI 版本的轻量级 sprite sheet 帧动画。
///
/// 通过 `CGImage.cropping(to:)` 按像素显式裁出当前帧，再交给 SwiftUI 渲染，
/// 避免 `.offset()` 在不同屏幕缩放下算错的问题。
/// 自动从 `NSImage` 与 `CGImage` 的尺寸推算像素/点比例（@1x / @2x / @3x），
/// 保证 `SpriteSheetConfig.frameSize`（单位：pt）始终对齐真实像素边界。
struct SpriteFrameAnimationView: View {
    let config: SpriteSheetConfig
    var fps: Double = 24
    var displaySize: CGFloat? = nil

    var body: some View {
        let interval = 1.0 / max(fps, 1)
        let rows = (config.totalFrames + config.columns - 1) / config.columns
        let renderSize = displaySize ?? config.frameSize

        TimelineView(.periodic(from: .now, by: interval)) { context in
            let frameIndex = config.totalFrames > 0
                ? Int(context.date.timeIntervalSinceReferenceDate / interval) % config.totalFrames
                : 0

            spriteImage(frameIndex: frameIndex, rows: rows, renderSize: renderSize)
        }
        .frame(width: renderSize, height: renderSize)
    }

    @ViewBuilder
    private func spriteImage(frameIndex: Int, rows: Int, renderSize: CGFloat) -> some View {
        let col = frameIndex % config.columns
        let row = frameIndex / config.columns

        if let nsImage = NSImage(named: config.imageName),
           let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let pixelFrameWidth = floor(CGFloat(cgImage.width) / CGFloat(config.columns))
            let pixelFrameHeight = floor(CGFloat(cgImage.height) / CGFloat(rows))

            let cropRect = CGRect(
                x: floor(CGFloat(col) * pixelFrameWidth),
                y: floor(CGFloat(rows - 1 - row) * pixelFrameHeight),
                width: pixelFrameWidth,
                height: pixelFrameHeight
            )

            if let croppedCGImage = cgImage.cropping(to: cropRect) {
                let cropped = NSImage(
                    cgImage: croppedCGImage,
                    size: NSSize(width: config.frameSize, height: config.frameSize)
                )
                Image(nsImage: cropped)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: renderSize, height: renderSize)
            } else {
                Color.clear
            }
        } else {
            Color.clear
        }
    }
}
