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
    private var cancellables = Set<AnyCancellable>()

    init() {
        petSize = SettingsManager.shared.petSize
        animationManager.loadSpriteSheets()
        currentFrame = animationManager.currentFrame
        setupBindings()
        setupSettingsBindings()
    }

    private func setupBindings() {
        behaviorManager.onTick = { [weak self] in
            guard let self = self else { return }
            self.animationManager.tick()
            self.currentFrame = self.animationManager.currentFrame
        }

        behaviorManager.onFacingRightChanged = { [weak self] value in
            self?.facingRight = value
        }

        behaviorManager.onDragStateChanged = { [weak self] value in
            guard let self = self else { return }
            self.isDragging = value
            if value {
                self.animationManager.switchToDrag()
            } else {
                self.animationManager.switchToRun()
            }
            self.currentFrame = self.animationManager.currentFrame
        }

        behaviorManager.onSleepStateChanged = { [weak self] isSleeping in
            guard let self = self else { return }
            if isSleeping {
                self.animationManager.switchToSleep()
            } else {
                self.animationManager.switchToRun()
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

    /// 唤醒睡眠中的桌宠（双击触发）
    func wakeUp() {
        if behaviorManager.isSleeping {
            behaviorManager.wakeUp()
            animationManager.switchToRun()
            currentFrame = animationManager.currentFrame
        }
    }

    /// 隐藏宠物窗口时进入睡眠并停止计时器
    func sleep() {
        behaviorManager.sleep()
        behaviorManager.stopAllTimers()
    }

    /// 显示宠物窗口时唤醒并重新开始行走
    func wakeUpAndWalk() {
        behaviorManager.wakeUp()
        behaviorManager.startWalking()
        isDragging = false
        animationManager.switchToRun()
        currentFrame = animationManager.currentFrame
    }

    // MARK: - Settings Bindings

    private func setupSettingsBindings() {
        SettingsManager.shared.$petSizeScale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let newSize = SettingsManager.shared.petSize
                guard self.petSize != newSize else { return }
                self.petSize = newSize
                self.resizeWindow(to: newSize)
            }
            .store(in: &cancellables)
    }

    private func resizeWindow(to size: CGSize) {
        guard let window = window else { return }
        var frame = window.frame
        let oldCenter = CGPoint(x: frame.midX, y: frame.midY)
        frame.size = size
        frame.origin.x = oldCenter.x - size.width / 2
        frame.origin.y = oldCenter.y - size.height / 2
        window.setFrame(frame, display: true, animate: false)
    }
}
