import SwiftUI
import Combine

final class PetViewModel: ObservableObject {
    @Published var facingRight = true
    @Published var isDragging = false
    @Published var isTired = false
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
                // 拖拽结束：若 pet 处于 tired 状态，保持 sleep 动画；否则回到 run
                if self.behaviorManager.isTired {
                    self.animationManager.setAnimation(.sleep)
                } else {
                    self.animationManager.resetToRun()
                }
            }
            self.currentFrame = self.animationManager.currentFrame
        }

        behaviorManager.onTiredStateChanged = { [weak self] value in
            guard let self = self else { return }
            self.isTired = value
            if value {
                self.animationManager.setAnimation(.sleep)
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

    func playAnimation(_ kind: PetAnimation) {
        animationManager.setAnimation(kind)
        currentFrame = animationManager.currentFrame
    }

    /// 双击唤醒：让 pet 从 tired/sleep 状态回到 run。
    func wakeUp() {
        behaviorManager.wakeUp()
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
