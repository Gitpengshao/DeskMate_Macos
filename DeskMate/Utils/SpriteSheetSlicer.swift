import AppKit

enum SpriteSheetSlicer {
    static func sliceSpriteSheet(config: SpriteSheetConfig) -> [NSImage] {
        guard let image = NSImage(named: config.imageName),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Warning: \(config.imageName).png not found in assets")
            return []
        }

        let rows = (config.totalFrames + config.columns - 1) / config.columns

        let rawFrameWidth: CGFloat
        let rawFrameHeight: CGFloat
        if let sourceSize = config.sourceFrameSize {
            rawFrameWidth = sourceSize.width
            rawFrameHeight = sourceSize.height
        } else {
            rawFrameWidth = CGFloat(cgImage.width) / CGFloat(config.columns)
            rawFrameHeight = CGFloat(cgImage.height) / CGFloat(rows)
        }

        var frames: [NSImage] = []

        for i in 0..<config.totalFrames {
            let col = i % config.columns
            let row = i / config.columns

            // CGImage 坐标系原点在左上角，行号从上到下递增，因此直接用 row * frameHeight。
            let cropRect = CGRect(
                x: floor(CGFloat(col) * rawFrameWidth),
                y: floor(CGFloat(row) * rawFrameHeight),
                width: floor(rawFrameWidth),
                height: floor(rawFrameHeight)
            )

            guard cropRect.minX >= 0,
                  cropRect.minY >= 0,
                  cropRect.maxX <= CGFloat(cgImage.width),
                  cropRect.maxY <= CGFloat(cgImage.height),
                  let croppedCGImage = cgImage.cropping(to: cropRect) else {
                continue
            }

            let frame = NSImage(
                cgImage: croppedCGImage,
                size: NSSize(width: config.frameSize, height: config.frameSize)
            )
            frames.append(frame)
        }

        return frames
    }
}
