import AppKit

final class PetBehaviorManager {
    // MARK: - Callbacks

    var onTick: (() -> Void)?
    var onFacingRightChanged: ((Bool) -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?
    var onTiredStateChanged: ((Bool) -> Void)?

    // MARK: - State

    private var walkTimer: Timer?
    private var mouseDownTimer: Timer?
    private var walkSpeed: CGFloat = 2.0
    private var walkDirection: CGFloat = 1   // 1 = right, -1 = left
    private var isMouseDown = false
    private(set) var isDragging = false
    private(set) var facingRight = true

    // 「走累」状态机：walkElapsed 在 !isDragging && !isTired 时累加，
    // 达到 tiredThreshold 后切到 tired 状态并触发 onTiredStateChanged(true)
    private var walkElapsed: TimeInterval = 0
    private let tiredThreshold: TimeInterval = 15.0
    private(set) var isTired: Bool = false

    // 拖拽锚点：以绝对坐标为基准，避免丢失事件导致的累积漂移
    private var dragAnchorMouseLocation: NSPoint?
    private var dragAnchorWindowOrigin: NSPoint?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    weak var window: NSWindow?

    // MARK: - Walking Behavior

    func startWalking() {
        walkTimer?.invalidate()
        let wasTired = isTired
        walkElapsed = 0
        isTired = false
        walkTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.onTick?()
            self?.walkStep()
            self?.tickTiredness()
        }
        if wasTired {
            onTiredStateChanged?(false)
        }
    }

    /// 累加 walkElapsed；达到阈值后切到 tired 状态。
    /// 仅在「未拖拽 且 未 tired」时累加 — 拖拽期间不算走路，tired 后不再增长。
    private func tickTiredness() {
        guard !isDragging, !isTired else { return }
        walkElapsed += 0.016
        if walkElapsed >= tiredThreshold {
            isTired = true
            onTiredStateChanged?(true)
        }
    }

    /// 用户主动唤醒：重置 tired 状态并清零累加器，由双击手势触发。
    func wakeUp() {
        guard isTired else { return }
        isTired = false
        walkElapsed = 0
        onTiredStateChanged?(false)
    }

    /// 获取当前窗口所在的屏幕。
    /// 对于 stationary NSPanel，window.screen 为 nil，需要遍历所有屏幕来查找。
    private func screenContainingWindow(_ window: NSWindow) -> NSScreen? {
        if let screen = window.screen {
            return screen
        }
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(window.frame) {
                return screen
            }
        }
        return NSScreen.main
    }

    private func walkStep() {
        guard let window = window, !isDragging, !isTired else { return }
        guard let screen = screenContainingWindow(window) else { return }

        let screenFrame = screen.visibleFrame
        var windowFrame = window.frame
        let dx = walkSpeed * walkDirection

        windowFrame.origin.x += dx

        // 边界碰撞检测并反转方向
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
        // 本地 monitor：处理 app 内部的事件
        let handler: (NSEvent) -> NSEvent = { [weak self] event in
            self?.handle(event: event)
            return event
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged],
            handler: handler
        )

        // 全局 monitor：当鼠标离开 app 窗口时仍能捕获 drag/up 事件，
        // 保证拖拽过程不会因为鼠标越界而中断
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .leftMouseDragged]
        ) { [weak self] event in
            self?.handle(event: event)
        }
    }

    private func handle(event: NSEvent) {
        guard let window = self.window else { return }

        let mouseScreenPoint = NSEvent.mouseLocation
        let isInPetWindow = window.isVisible && window.frame.contains(mouseScreenPoint)

        switch event.type {
        case .leftMouseDown:
            // 仅当点击发生在桌宠窗口内才开始拖拽判断
            if isInPetWindow {
                handleMouseDown()
            }
        case .leftMouseUp:
            handleMouseUp()
        case .leftMouseDragged:
            // 一旦进入拖拽状态，无论鼠标是否还在窗口内都持续处理
            // 这样即使鼠标移动得很快、暂时离开桌宠窗口，仍然能跟手
            if isDragging {
                handleMouseDrag()
            }
        default:
            break
        }
    }

    private func handleMouseDown() {
        isMouseDown = true
        mouseDownTimer?.invalidate()
        mouseDownTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            guard let self = self, self.isMouseDown else { return }
            guard let window = self.window else { return }
            // 进入拖拽时记录鼠标和窗口的绝对位置作为锚点
            self.dragAnchorMouseLocation = NSEvent.mouseLocation
            self.dragAnchorWindowOrigin = window.frame.origin
            self.isDragging = true
            self.onDragStateChanged?(true)
        }
    }

    private func handleMouseUp() {
        isMouseDown = false
        mouseDownTimer?.invalidate()
        mouseDownTimer = nil
        dragAnchorMouseLocation = nil
        dragAnchorWindowOrigin = nil
        if isDragging {
            isDragging = false
            onDragStateChanged?(false)
        }
    }

    private func handleMouseDrag() {
        guard isDragging, let window = window else { return }
        guard let anchorMouse = dragAnchorMouseLocation,
              let anchorOrigin = dragAnchorWindowOrigin else { return }
        guard let screen = screenContainingWindow(window) else { return }

        let screenFrame = screen.visibleFrame
        let currentMouse = NSEvent.mouseLocation

        // 基于绝对坐标计算窗口新位置，避免丢失事件导致的不跟手/漂移
        let origin = NSPoint(
            x: anchorOrigin.x + (currentMouse.x - anchorMouse.x),
            y: anchorOrigin.y + (currentMouse.y - anchorMouse.y)
        )
        var frame = NSRect(origin: origin, size: window.frame.size)

        // 边界钳制
        if frame.maxX > screenFrame.maxX {
            frame.origin.x = screenFrame.maxX - frame.width
        }
        if frame.minX < screenFrame.minX {
            frame.origin.x = screenFrame.minX
        }
        if frame.maxY > screenFrame.maxY {
            frame.origin.y = screenFrame.maxY - frame.height
        }
        if frame.minY < screenFrame.minY {
            frame.origin.y = screenFrame.minY
        }

        window.setFrame(frame, display: true)
    }

    // MARK: - Cleanup

    func stopAllTimers() {
        walkTimer?.invalidate()
        walkTimer = nil
        mouseDownTimer?.invalidate()
        mouseDownTimer = nil
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
    }

    /// 重置拖拽状态
    func resetDragState() {
        isMouseDown = false
        isDragging = false
        mouseDownTimer?.invalidate()
        mouseDownTimer = nil
        dragAnchorMouseLocation = nil
        dragAnchorWindowOrigin = nil
    }
}
