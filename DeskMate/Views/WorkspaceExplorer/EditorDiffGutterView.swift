import AppKit

#if canImport(CodeEditTextView)
import CodeEditTextView
#endif

/// 编辑器左侧 diff gutter 覆盖视图 — 在修改行的行号旁绘制红/绿/黄标记。
///
/// 同时兼容 `CodeEditTextView.TextView`（CodeEditSourceEditor）与原生 `NSTextView`（降级编辑器）。
final class EditorDiffGutterView: NSView {
    weak var textView: NSView?
    var markers: [TextDiffer.LineDiffMarker] = []

    private let markerWidth: CGFloat = 3.0

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for marker in markers {
            guard var rect = rectForMarker(marker) else { continue }

            // 限制绘制区域在 dirtyRect 内，并统一宽度为 marker 条。
            rect.origin.x = 0
            rect.size.width = markerWidth

            let color: NSColor
            switch marker.kind {
            case .added:
                color = NSColor(red: 0.290, green: 0.820, blue: 0.420, alpha: 1.0)
            case .modified:
                color = NSColor(red: 1.000, green: 0.600, blue: 0.200, alpha: 1.0)
            case .deleted:
                color = NSColor(red: 0.960, green: 0.380, blue: 0.380, alpha: 1.0)
            }

            color.setFill()
            rect.fill()
        }
    }

    /// 根据底层 text view 类型计算 marker 所在行的矩形（视图坐标系）。
    private func rectForMarker(_ marker: TextDiffer.LineDiffMarker) -> NSRect? {
        #if canImport(CodeEditTextView)
        if let textView = textView as? CodeEditTextView.TextView,
           let linePosition = textView.layoutManager.textLineForIndex(marker.newLineNumber) {
            return NSRect(
                x: 0,
                y: linePosition.yPos,
                width: markerWidth,
                height: linePosition.height
            )
        }
        #endif

        guard let textView = textView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }

        let text = textView.string as NSString
        guard marker.newLineNumber < text.dm_numberOfLines() else { return nil }

        let lineRange = text.dm_rangeOfLine(marker.newLineNumber)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        // NSLayoutManager 返回的是 text container 坐标，需转换到 text view / marker view 坐标系。
        rect.origin.y += textView.textContainerOrigin.y
        return rect
    }

    func update(markers: [TextDiffer.LineDiffMarker]) {
        self.markers = markers
        setNeedsDisplay(bounds)
    }

    /// 让鼠标事件穿透到下方的 gutter / text view。
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// MARK: - NSString 行号辅助

extension NSString {
    /// 文本总行数（空文本返回 1，保证至少有一行可绘制区域）。
    func dm_numberOfLines() -> Int {
        guard length > 0 else { return 1 }
        var count = 0
        var index = 0
        while index < length {
            var lineEnd = 0
            getLineStart(nil, end: &lineEnd, contentsEnd: nil, for: NSRange(location: index, length: 0))
            index = lineEnd
            count += 1
        }
        return max(count, 1)
    }

    /// 返回指定 0-based 行的字符范围。
    func dm_rangeOfLine(_ targetLine: Int) -> NSRange {
        guard length > 0 else { return NSRange(location: 0, length: 0) }

        var line = 0
        var index = 0
        while index < length && line <= targetLine {
            var lineStart = 0
            var lineEnd = 0
            getLineStart(&lineStart, end: &lineEnd, contentsEnd: nil, for: NSRange(location: index, length: 0))
            if line == targetLine {
                return NSRange(location: lineStart, length: lineEnd - lineStart)
            }
            index = lineEnd
            line += 1
        }
        return NSRange(location: length, length: 0)
    }
}
