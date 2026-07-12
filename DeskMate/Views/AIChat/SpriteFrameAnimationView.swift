import SwiftUI
import AppKit

/// 精灵图帧动画视图 — SwiftUI 版本的轻量级 sprite sheet 帧动画。
///
/// 通过 `SpriteSheetSlicer` 预先把整张贴图切成帧数组并缓存，
/// `TimelineView` 只负责按索引切换，避免每帧都重新裁切图片。
struct SpriteFrameAnimationView: View {
    let config: SpriteSheetConfig
    var fps: Double = 24
    var displaySize: CGFloat? = nil

    var body: some View {
        let interval = 1.0 / max(fps, 1)
        let renderSize = displaySize ?? config.frameSize
        let frames = cachedFrames()

        TimelineView(.periodic(from: .now, by: interval)) { context in
            let frameIndex = config.totalFrames > 0
                ? Int(context.date.timeIntervalSinceReferenceDate / interval) % config.totalFrames
                : 0

            if frames.indices.contains(frameIndex) {
                Image(nsImage: frames[frameIndex])
                    .resizable()
                    .interpolation(.none)
                    .frame(width: renderSize, height: renderSize)
            } else {
                Color.clear
                    .frame(width: renderSize, height: renderSize)
            }
        }
        .frame(width: renderSize, height: renderSize)
    }

    // MARK: - Frame Cache

    private static var cache: [String: [NSImage]] = [:]

    private func cachedFrames() -> [NSImage] {
        let key = cacheKey
        if let cached = Self.cache[key] {
            return cached
        }
        let frames = SpriteSheetSlicer.sliceSpriteSheet(config: config)
        Self.cache[key] = frames
        return frames
    }

    private var cacheKey: String {
        [
            config.imageName,
            String(config.columns),
            String(config.totalFrames),
            String(describing: config.frameSize),
            String(describing: config.sourceFrameSize?.width ?? 0),
            String(describing: config.sourceFrameSize?.height ?? 0)
        ].joined(separator: "|")
    }
}
