import AppKit

final class PetAnimationManager {
    private var runFrames: [NSImage] = []
    private var dragFrames: [NSImage] = []
    private var currentFrameIndex: Int = 0
    private var animTick: Int = 0
    private let animSpeedDivider: Int = 3

    var currentFrame: NSImage?

    // MARK: - Sprite Sheet Loading

    func loadSpriteSheets() {
        runFrames = sliceSpriteSheet(config: SpriteSheets.run)
        dragFrames = sliceSpriteSheet(config: SpriteSheets.drag)
        currentFrame = runFrames.first
    }

    private func sliceSpriteSheet(config: SpriteSheetConfig) -> [NSImage] {
        guard let image = NSImage(named: config.imageName) else {
            print("Warning: \(config.imageName).png not found in assets")
            return []
        }

        var frames: [NSImage] = []
        let rows = (config.totalFrames + config.columns - 1) / config.columns

        for i in 0..<config.totalFrames {
            let col = i % config.columns
            let row = i / config.columns

            // NSImage coordinate system: (0,0) is bottom-left
            // Sprite sheet rows go top-to-bottom
            let srcY = CGFloat(rows - 1 - row) * config.frameSize
            let srcX = CGFloat(col) * config.frameSize
            let rect = NSRect(x: srcX, y: srcY, width: config.frameSize, height: config.frameSize)

            let frameImage = NSImage(size: NSSize(width: config.frameSize, height: config.frameSize))
            frameImage.lockFocus()
            image.draw(
                in: NSRect(x: 0, y: 0, width: config.frameSize, height: config.frameSize),
                from: rect,
                operation: .copy,
                fraction: 1.0
            )
            frameImage.unlockFocus()
            frames.append(frameImage)
        }

        return frames
    }

    // MARK: - Animation Tick

    func tick(isDragging: Bool) {
        animTick += 1
        if animTick % animSpeedDivider == 0 {
            advanceFrame(isDragging: isDragging)
        }
    }

    private func advanceFrame(isDragging: Bool) {
        let frames = isDragging ? dragFrames : runFrames
        guard !frames.isEmpty else { return }
        currentFrameIndex = (currentFrameIndex + 1) % frames.count
        currentFrame = frames[currentFrameIndex]
    }

    // MARK: - State Reset

    func resetToRun() {
        currentFrameIndex = 0
        animTick = 0
        currentFrame = runFrames.first
    }

    func resetToDrag() {
        currentFrameIndex = 0
        animTick = 0
        currentFrame = dragFrames.first
    }
}
