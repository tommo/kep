import AppKit
import CoreGraphics

/// Bounds math for free-canvas panning. A plain NSClipView clamps scrolling to
/// the document rect — that's the "scrolling a document" feel. We instead allow
/// panning a generous margin *past* the content so the canvas feels like
/// something you grab and move (Figma / Miro / Obsidian-canvas style), while
/// still being bounded (not infinite). Pure so it's unit-testable.
public enum CanvasScroll {
    /// Clamp `proposed` clip origin so the canvas pans freely but the viewport
    /// always overlaps the **content** by at least `keepVisible` points on each
    /// axis. Constraining against the content rect (not the document frame) is
    /// what stops the view getting parked in the empty padding around the graph
    /// — you can never scroll the content out of sight or lock onto blank space.
    /// Each axis independent.
    public static func constrainedOrigin(
        proposed: CGPoint, viewport: CGSize, content: CGRect, keepVisible: CGFloat
    ) -> CGPoint {
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            min(max(v, lo), max(lo, hi))
        }
        // Keep ≥ keepX of the content's x-extent inside the viewport (and never
        // require more than the content actually has).
        let keepX = min(keepVisible, content.width)
        let keepY = min(keepVisible, content.height)
        // Visible x-range [origin.x, origin.x+vp] must overlap [content.minX,
        // content.maxX] by ≥ keepX → origin.x ∈ [content.minX + keepX - vp,
        // content.maxX - keepX].
        let minX = content.minX + keepX - viewport.width
        let maxX = content.maxX - keepX
        let minY = content.minY + keepY - viewport.height
        let maxY = content.maxY - keepY
        return CGPoint(x: clamp(proposed.x, minX, maxX), y: clamp(proposed.y, minY, maxY))
    }
}

/// NSClipView that pans freely a screenful beyond the content instead of
/// clamping to the document like a scroll view. Used by the mindmap canvas so
/// scroll/drag pans rather than "scrolls a doc".
///
/// Pattern follows Apple's PhotoEditor `CanvasClipView` (override
/// `constrainBoundsRect` to control the allowed bounds) plus Helftone's
/// infinite-NSScrollView fix for the AppKit smooth-scroll bug (override
/// `scroll(to:)` to set the bounds origin directly).
final class CanvasClipView: NSClipView {
    /// Keep at least this much of the content on screen when over-panning.
    static let keepVisible: CGFloat = 96

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        guard let doc = documentView else { return super.constrainBoundsRect(proposedBounds) }
        // Constrain against the actual content extent, not the (padded /
        // viewport-filling) document frame, so the viewport can't park on empty
        // canvas. Fall back to the doc frame before the first layout.
        let content = (doc as? MindMapView).map { $0.contentBounds }
            .flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
            ?? CGRect(origin: .zero, size: doc.frame.size)
        let origin = CanvasScroll.constrainedOrigin(
            proposed: proposedBounds.origin,
            viewport: proposedBounds.size,
            content: content,
            keepVisible: Self.keepVisible)
        return NSRect(origin: origin, size: proposedBounds.size)
    }
}
