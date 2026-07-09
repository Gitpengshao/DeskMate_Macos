import AppKit

#if canImport(CodeEditSourceEditor)
import CodeEditSourceEditor
#endif

#if canImport(CodeEditTextView)
import CodeEditTextView
#endif

#if canImport(CodeEditSourceEditor)
/// 将 `EditorDiffGutterView` 接入 `CodeEditSourceEditor` 的 coordinator。
///
/// 通过 `TextViewCoordinator` 在编辑器 gutter 上绘制当前内容相对基线的变更条。
@MainActor
final class DiffGutterCoordinator: TextViewCoordinator {
    private weak var controller: TextViewController?
    private var markerView: EditorDiffGutterView?
    private var baseContent: String = ""
    private var scrollObserver: Any?

    /// 更新 diff 基线。通常由 `CodeEditorView` 在打开文件或保存后调用。
    func setBaseContent(_ content: String) {
        DMLogger.log("DiffGutterCoordinator setBaseContent: length=\(content.count)", name: "DiffDebug")
        baseContent = content
        updateMarkers()
    }

    func prepareCoordinator(controller: TextViewController) {
        // prepareCoordinator 在 controller 初始化时调用，此时 scrollView/gutterView 尚未创建。
        // 保存弱引用，等 controllerDidAppear 时再挂载 marker view。
        DMLogger.log("DiffGutterCoordinator prepareCoordinator", name: "DiffDebug")
        self.controller = controller
    }

    func controllerDidAppear(controller: TextViewController) {
        DMLogger.log("DiffGutterCoordinator controllerDidAppear", name: "DiffDebug")
        installMarkerViewIfNeeded(controller: controller)

        // 滚动时 gutterView 会重绘自身，但子 view 不会自动被标记为需要重绘，因此显式监听。
        if scrollObserver == nil, let contentView = controller.scrollView?.contentView {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: contentView,
                queue: .main
            ) { [weak self] _ in
                self?.markerView?.setNeedsDisplay(self?.markerView?.bounds ?? .zero)
            }
        }

        updateMarkers(controller: controller)
    }

    func textViewDidChangeText(controller: TextViewController) {
        DMLogger.log("DiffGutterCoordinator textViewDidChangeText", name: "DiffDebug")
        updateMarkers(controller: controller)
    }

    func destroy() {
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
            scrollObserver = nil
        }
        markerView?.removeFromSuperview()
        markerView = nil
        controller = nil
    }

    private func installMarkerViewIfNeeded(controller: TextViewController) {
        guard markerView?.superview == nil,
              let gutterView = controller.scrollView?.subviews.first(where: { $0 is GutterView }) as? GutterView else {
            DMLogger.log("DiffGutterCoordinator installMarkerView skipped: markerSuperview=\(markerView?.superview != nil), gutterFound=\(controller.scrollView?.subviews.contains(where: { $0 is GutterView }) ?? false)", name: "DiffDebug")
            return
        }

        DMLogger.log("DiffGutterCoordinator installMarkerView: gutterBounds=\(gutterView.bounds)", name: "DiffDebug")
        let markerView = EditorDiffGutterView(frame: gutterView.bounds)
        markerView.autoresizingMask = NSView.AutoresizingMask.width.union(.height)
        markerView.textView = controller.textView
        gutterView.addSubview(markerView)
        self.markerView = markerView
    }

    private func updateMarkers(controller: TextViewController? = nil) {
        let target = controller ?? self.controller
        guard let target else {
            DMLogger.log("DiffGutterCoordinator updateMarkers skipped: no controller", name: "DiffDebug")
            return
        }
        let markers = TextDiffer.lineMarkers(old: baseContent, new: target.text)
        let markerDesc = markers.map { "\($0.newLineNumber):\($0.kind)" }.joined(separator: ",")
        DMLogger.log("DiffGutterCoordinator updateMarkers: baseLength=\(baseContent.count), currentLength=\(target.text.count), markerCount=\(markers.count), markers=[\(markerDesc)]", name: "DiffDebug")
        markerView?.update(markers: markers)
    }
}

#else

/// CodeEditSourceEditor 不可用时提供一个空实现，避免调用方写大量条件编译。
@MainActor
final class DiffGutterCoordinator {
    func setBaseContent(_ content: String) { }
}

#endif
