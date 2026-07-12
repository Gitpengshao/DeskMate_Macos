import AppKit

final class PetAnimationManager {
    private var runFrames: [NSImage] = []
    private var dragFrames: [NSImage] = []
    private var sleepFrames: [NSImage] = []
    private var leaveFrames: [NSImage] = []
    private var idleFrames: [NSImage] = []
    private var walkFrames: [NSImage] = []
    private var workAtDeskFrames: [NSImage] = []
    private var currentFrameIndex: Int = 0
    private var animTick: Int = 0
    private let animSpeedDivider: Int = 3

    private(set) var currentAnimation: PetAnimation = .run
    var currentFrame: NSImage?

    // MARK: - Sprite Sheet Loading

    func loadSpriteSheets() {
        runFrames = sliceSpriteSheet(config: SpriteSheets.run)
        dragFrames = sliceSpriteSheet(config: SpriteSheets.drag)
        sleepFrames = sliceSpriteSheet(config: SpriteSheets.sleep)
        leaveFrames = sliceSpriteSheet(config: SpriteSheets.leave)
        idleFrames = sliceSpriteSheet(config: SpriteSheets.idle)
        walkFrames = sliceSpriteSheet(config: SpriteSheets.walk)
        workAtDeskFrames = sliceSpriteSheet(config: SpriteSheets.workAtDesk)
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

    func tick() {
        animTick += 1
        if animTick % animSpeedDivider == 0 {
            advanceFrame()
        }
    }

    private func advanceFrame() {
        let frames: [NSImage]
        switch currentAnimation {
        case .run:   frames = runFrames
        case .drag:  frames = dragFrames
        case .sleep: frames = sleepFrames
        case .leave: frames = leaveFrames
        case .idle:  frames = idleFrames
        case .walk:  frames = walkFrames
        case .workAtDesk: frames = workAtDeskFrames
        case .think, .work: frames = runFrames
        }
        guard !frames.isEmpty else { return }
        currentFrameIndex = (currentFrameIndex + 1) % frames.count
        currentFrame = frames[currentFrameIndex]
    }

    // MARK: - Animation State Switch

    func switchToRun() {
        currentAnimation = .run
        currentFrameIndex = 0
        animTick = 0
        currentFrame = runFrames.first
    }

    func switchToDrag() {
        currentAnimation = .drag
        currentFrameIndex = 0
        animTick = 0
        currentFrame = dragFrames.first
    }

    func switchToSleep() {
        currentAnimation = .sleep
        currentFrameIndex = 0
        animTick = 0
        currentFrame = sleepFrames.first
    }

    func switchToLeave() {
        currentAnimation = .leave
        currentFrameIndex = 0
        animTick = 0
        currentFrame = leaveFrames.first
    }

    func switchToIdle() {
        currentAnimation = .idle
        currentFrameIndex = 0
        animTick = 0
        currentFrame = idleFrames.first
    }

    func switchToWalk() {
        currentAnimation = .walk
        currentFrameIndex = 0
        animTick = 0
        currentFrame = walkFrames.first
    }

    func switchToWorkAtDesk() {
        currentAnimation = .workAtDesk
        currentFrameIndex = 0
        animTick = 0
        currentFrame = workAtDeskFrames.first
    }

    // MARK: - State Reset (kept for backward compatibility)

    func resetToRun() {
        switchToRun()
    }

    func resetToDrag() {
        switchToDrag()
    }
}