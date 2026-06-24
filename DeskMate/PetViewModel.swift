import SwiftUI
import AppKit
import Combine

class PetViewModel: ObservableObject {
    @Published var facingRight = true
    @Published var isDragging = false
    @Published var currentFrame: NSImage?
    @Published var petSize: CGSize = CGSize(width: 180, height: 180)

    weak var window: NSWindow?

    private var walkTimer: Timer?
    private var walkSpeed: CGFloat = 2.0
    private var walkDirection: CGFloat = 1  // 1 = right, -1 = left
    private var mouseDownTimer: Timer?
    private var isMouseDown = false

    // Sprite sheet frames
    private var runFrames: [NSImage] = []
    private var dragFrames: [NSImage] = []
    private var currentFrameIndex: Int = 0
    private var animTick: Int = 0
    private let animSpeedDivider: Int = 3  // advance frame every N ticks

    private let frameSize: CGFloat = 180

    init() {
        petSize = CGSize(width: frameSize, height: frameSize)
        loadSpriteSheets()
    }

    // MARK: - Sprite Sheet Loading

    private func loadSpriteSheets() {
        runFrames = sliceSpriteSheet(named: "run", columns: 6, totalFrames: 21)
        dragFrames = sliceSpriteSheet(named: "drag", columns: 6, totalFrames: 26)
        currentFrame = runFrames.first
    }

    private func sliceSpriteSheet(named name: String, columns: Int, totalFrames: Int) -> [NSImage] {
        guard let image = NSImage(named: name) else {
            print("Warning: \(name).png not found in assets")
            return []
        }

        var frames: [NSImage] = []
        let frameW = frameSize
        let frameH = frameSize
        let rows = (totalFrames + columns - 1) / columns

        // NSImage coordinate system: (0,0) is bottom-left
        // Our sprite sheet rows go top-to-bottom
        for i in 0..<totalFrames {
            let col = i % columns
            let row = i / columns

            let srcY = CGFloat(rows - 1 - row) * frameH
            let srcX = CGFloat(col) * frameW
            let rect = NSRect(x: srcX, y: srcY, width: frameW, height: frameH)

            let frameImage = NSImage(size: NSSize(width: frameW, height: frameH))
            frameImage.lockFocus()
            image.draw(in: NSRect(x: 0, y: 0, width: frameW, height: frameH),
                       from: rect,
                       operation: .copy,
                       fraction: 1.0)
            frameImage.unlockFocus()
            frames.append(frameImage)
        }

        return frames
    }

    // MARK: - Walking Behavior

    func startWalking() {
        currentFrame = runFrames.first
        currentFrameIndex = 0
        animTick = 0

        // Animation + walk timer (~60fps)
        walkTimer?.invalidate()
        walkTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        animTick += 1
        if animTick % animSpeedDivider == 0 {
            advanceFrame()
            walkStep()
        }
    }

    private func advanceFrame() {
        let frames = isDragging ? dragFrames : runFrames
        guard !frames.isEmpty else { return }
        currentFrameIndex = (currentFrameIndex + 1) % frames.count
        currentFrame = frames[currentFrameIndex]
    }

    // MARK: - Mouse Drag Handling

    func handleMouseDown() {
        isMouseDown = true
        mouseDownTimer?.invalidate()
        // 长按 0.25 秒后切换到 drag 动画
        mouseDownTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self = self, self.isMouseDown else { return }
            self.isDragging = true
            self.currentFrameIndex = 0
            self.animTick = 0
            self.currentFrame = self.dragFrames.first
        }
    }

    func handleMouseUp() {
        isMouseDown = false
        mouseDownTimer?.invalidate()
        mouseDownTimer = nil
        if isDragging {
            isDragging = false
            currentFrameIndex = 0
            animTick = 0
            currentFrame = runFrames.first
        }
    }

    private func walkStep() {
        guard let window = window, !isDragging else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        var windowFrame = window.frame
        let dx = walkSpeed * walkDirection

        windowFrame.origin.x += dx

        if windowFrame.maxX > screenFrame.maxX {
            windowFrame.origin.x = screenFrame.maxX - windowFrame.width
            walkDirection = -1
            facingRight = false
        } else if windowFrame.minX < screenFrame.minX {
            windowFrame.origin.x = screenFrame.minX
            walkDirection = 1
            facingRight = true
        }

        window.setFrame(windowFrame, display: true)
    }

    func stopAllTimers() {
        walkTimer?.invalidate()
        walkTimer = nil
        mouseDownTimer?.invalidate()
        mouseDownTimer = nil
    }
}
