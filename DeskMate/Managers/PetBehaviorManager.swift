import AppKit

final class PetBehaviorManager {
    // MARK: - Callbacks

    var onTick: (() -> Void)?
    var onFacingRightChanged: ((Bool) -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?

    // MARK: - State

    private var walkTimer: Timer?
    private var mouseDownTimer: Timer?
    private var walkSpeed: CGFloat = 2.0
    private var walkDirection: CGFloat = 1   // 1 = right, -1 = left
    private var isMouseDown = false
    private(set) var isDragging = false
    private(set) var facingRight = true

    weak var window: NSWindow?

    // MARK: - Walking Behavior

    func startWalking() {
        walkTimer?.invalidate()
        walkTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.onTick?()
            self?.walkStep()
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
            onFacingRightChanged?(false)
        } else if windowFrame.minX < screenFrame.minX {
            windowFrame.origin.x = screenFrame.minX
            walkDirection = 1
            facingRight = true
            onFacingRightChanged?(true)
        }

        window.setFrame(windowFrame, display: true)
    }

    // MARK: - Mouse Drag Handling

    func setupMouseMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
            guard let self = self, let window = self.window else { return event }

            // 使用 NSEvent.mouseLocation 获取全局屏幕坐标，
            // 而非 event.locationInWindow（后者是相对于事件源窗口的坐标，
            // 当事件来自其他窗口（控制台等）时，用它做坐标转换会得到错误结果）
            let mouseScreenPoint = NSEvent.mouseLocation
            let isInPetWindow = window.isVisible && window.frame.contains(mouseScreenPoint)

            switch event.type {
            case .leftMouseDown:
                if isInPetWindow {
                    self.handleMouseDown()
                }
            case .leftMouseUp:
                self.handleMouseUp()
            case .leftMouseDragged:
                if isInPetWindow {
                    self.handleMouseDrag(deltaX: event.deltaX, deltaY: event.deltaY)
                }
            default:
                break
            }
            return event
        }
    }

    private func handleMouseDown() {
        isMouseDown = true
        mouseDownTimer?.invalidate()
        mouseDownTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self = self, self.isMouseDown else { return }
            self.isDragging = true
            self.onDragStateChanged?(true)
        }
    }

    private func handleMouseUp() {
        isMouseDown = false
        mouseDownTimer?.invalidate()
        mouseDownTimer = nil
        if isDragging {
            isDragging = false
            onDragStateChanged?(false)
        }
    }

    private func handleMouseDrag(deltaX: CGFloat, deltaY: CGFloat) {
        guard isDragging, let window = window else { return }
        var frame = window.frame
        frame.origin.x += deltaX
        frame.origin.y -= deltaY  // screen Y is flipped vs event deltaY
        window.setFrame(frame, display: true)
    }

    // MARK: - Cleanup

    func stopAllTimers() {
        walkTimer?.invalidate()
        walkTimer = nil
        mouseDownTimer?.invalidate()
        mouseDownTimer = nil
    }

    /// 重置拖拽状态
    func resetDragState() {
        isMouseDown = false
        isDragging = false
        mouseDownTimer?.invalidate()
        mouseDownTimer = nil
    }
}
