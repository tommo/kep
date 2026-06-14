import AppKit
import CoreGraphics

/// Bounds math for free-canvas panning. A plain NSClipView clamps scrolling to
/// the document rect — that's the "scrolling a document" feel. We instead allow
/// panning a generous margin *past* the content so the canvas feels like
/// something you grab and move (Figma / Miro / Obsidian-canvas style), while
/// still being bounded (not infinite). Pure so it's unit-testable.
public enum CanvasScroll {
    /// Clamp `proposed` clip origin to the document (origin (0,0), `doc` size)
    /// expanded by `margin` on every edge — each axis independently, so panning
    /// one axis can never disturb the other.
    public static func constrainedOrigin(
        proposed: CGPoint, viewport: CGSize, doc: CGSize, margin: CGSize
    ) -> CGPoint {
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            min(max(v, lo), max(lo, hi))
        }
        let minX = -margin.width
        let maxX = (doc.width - viewport.width) + margin.width
        let minY = -margin.height
        let maxY = (doc.height - viewport.height) + margin.height
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
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        guard let doc = documentView else { return super.constrainBoundsRect(proposedBounds) }
        // One visible screenful of slack on each edge.
        let margin = CGSize(width: proposedBounds.width, height: proposedBounds.height)
        let origin = CanvasScroll.constrainedOrigin(
            proposed: proposedBounds.origin,
            viewport: proposedBounds.size,
            doc: doc.frame.size,
            margin: margin)
        return NSRect(origin: origin, size: proposedBounds.size)
    }

    /// AppKit's mouse-wheel "smooth scrolling" can't cope with the bounds
    /// origin moving mid-scroll — it fights/ignores the change, which is what
    /// made panning feel like a stuck document. Forwarding straight to
    /// `setBoundsOrigin` (after applying our own constraint) bypasses that
    /// path so every scroll tick pans immediately. (Helftone's fix.)
    override func scroll(to newOrigin: NSPoint) {
        let constrained = constrainBoundsRect(NSRect(origin: newOrigin, size: bounds.size)).origin
        setBoundsOrigin(constrained)
    }
}
