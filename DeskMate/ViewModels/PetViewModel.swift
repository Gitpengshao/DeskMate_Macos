import SwiftUI
import Combine

final class PetViewModel: ObservableObject {
    @Published var facingRight = true
    @Published var isDragging = false
    @Published var currentFrame: NSImage?
    @Published var petSize: CGSize

    weak var window: NSWindow?

    private let animationManager = PetAnimationManager()
    private let behaviorManager = PetBehaviorManager()

    init() {
        petSize = SpriteSheets.petSize
        animationManager.loadSpriteSheets()
        currentFrame = animationManager.currentFrame
        setupBindings()
    }

    private func setupBindings() {
        behaviorManager.onTick = { [weak self] in
            guard let self = self else { return }
            self.animationManager.tick(isDragging: self.isDragging)
            self.currentFrame = self.animationManager.currentFrame
        }

        behaviorManager.onFacingRightChanged = { [weak self] value in
            self?.facingRight = value
        }

        behaviorManager.onDragStateChanged = { [weak self] value in
            guard let self = self else { return }
            self.isDragging = value
            if value {
                self.animationManager.resetToDrag()
            } else {
                self.animationManager.resetToRun()
            }
            self.currentFrame = self.animationManager.currentFrame
        }
    }

    func configure(with window: NSWindow) {
        self.window = window
        behaviorManager.window = window
        behaviorManager.setupMouseMonitoring()
        behaviorManager.startWalking()
    }

    func stopAllTimers() {
        behaviorManager.stopAllTimers()
    }

    /// 重置拖拽状态，确保动画回到 run
    func resetDragState() {
        behaviorManager.resetDragState()
        animationManager.resetToRun()
        isDragging = false
        currentFrame = animationManager.currentFrame
    }
}
