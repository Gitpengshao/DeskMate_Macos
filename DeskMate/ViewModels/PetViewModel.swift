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
    private var gatewayStatusCancellable: AnyCancellable?

    init() {
        petSize = SettingsManager.shared.petSize
        animationManager.loadSpriteSheets()
        currentFrame = animationManager.currentFrame
        setupBindings()
        setupGatewayStatusBinding()
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
                self.applyDefaultAnimation()
            }
            self.currentFrame = self.animationManager.currentFrame
        }

        behaviorManager.onSleepStateChanged = { [weak self] _ in
            guard let self = self else { return }
            self.applyDefaultAnimation()
        }
    }

    private func setupGatewayStatusBinding() {
        gatewayStatusCancellable = GatewayConnectionManager.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                self.behaviorManager.setGatewayAbnormal(status == .disconnected)
                if !self.behaviorManager.isDragging {
                    self.applyDefaultAnimation()
                }
            }
    }

    /// 根据网关状态与睡眠状态切回默认动画（拖拽状态需由调用方自行保持 drag）。
    private func applyDefaultAnimation() {
        if GatewayConnectionManager.shared.status == .disconnected {
            animationManager.switchToSick()
        } else if behaviorManager.isSleeping {
            animationManager.switchToSleep()
        } else {
            animationManager.switchToRun()
        }
        currentFrame = animationManager.currentFrame
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

    /// 重置拖拽状态，根据当前状态切回默认动画
    func resetDragState() {
        behaviorManager.resetDragState()
        isDragging = false
        applyDefaultAnimation()
    }

    /// 唤醒睡眠中的桌宠（双击触发）
    func wakeUp() {
        if behaviorManager.isSleeping {
            behaviorManager.wakeUp()
            applyDefaultAnimation()
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
        applyDefaultAnimation()
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
