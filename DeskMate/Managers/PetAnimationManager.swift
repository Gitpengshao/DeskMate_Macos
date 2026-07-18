import AppKit

final class PetAnimationManager {
    private var runFrames: [NSImage] = []
    private var dragFrames: [NSImage] = []
    private var thinkFrames: [NSImage] = []
    private var workFrames: [NSImage] = []
    private var sleepFrames: [NSImage] = []
    private var leaveFrames: [NSImage] = []
    private var idleFrames: [NSImage] = []
    private var walkFrames: [NSImage] = []
    private var workAtDeskFrames: [NSImage] = []
    private var listenFrames: [NSImage] = []
    private var sickFrames: [NSImage] = []
    private var currentFrameIndex: Int = 0
    private var animTick: Int = 0
    private let animSpeedDivider: Int = 3

    private(set) var currentAnimation: PetAnimation = .run
    var currentFrame: NSImage?

    // MARK: - Sprite Sheet Loading

    func loadSpriteSheets() {
        runFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.run)
        dragFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.drag)
        thinkFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.think)
        workFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.work)
        sleepFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.sleep)
        leaveFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.leave)
        idleFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.idle)
        walkFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.walk)
        workAtDeskFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.workAtDesk)
        listenFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.listen)
        sickFrames = SpriteSheetSlicer.sliceSpriteSheet(config: SpriteSheets.sick)
        currentFrame = runFrames.first
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
        case .think: frames = thinkFrames
        case .work:  frames = workFrames
        case .sleep: frames = sleepFrames
        case .leave: frames = leaveFrames
        case .idle:  frames = idleFrames
        case .walk:  frames = walkFrames
        case .workAtDesk: frames = workAtDeskFrames
        case .listen: frames = listenFrames
        case .sick:   frames = sickFrames
        case .downloadComplete, .downloading:
            // Onboarding-specific animations are not driven by PetAnimationManager.
            frames = []
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

    func switchToThink() {
        currentAnimation = .think
        currentFrameIndex = 0
        animTick = 0
        currentFrame = thinkFrames.first
    }

    func switchToWork() {
        currentAnimation = .work
        currentFrameIndex = 0
        animTick = 0
        currentFrame = workFrames.first
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

    func switchToListen() {
        currentAnimation = .listen
        currentFrameIndex = 0
        animTick = 0
        currentFrame = listenFrames.first
    }

    func switchToSick() {
        currentAnimation = .sick
        currentFrameIndex = 0
        animTick = 0
        currentFrame = sickFrames.first
    }

    // MARK: - State Reset (kept for backward compatibility)

    func resetToRun() {
        switchToRun()
    }

    func resetToDrag() {
        switchToDrag()
    }
}