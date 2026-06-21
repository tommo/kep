import AppKit
import CoreGraphics

/// Bounds math for free-canvas panning. A plain NSClipView clamps scrolling to
/// the document rect — that's the "scrolling a document" feel. We instead allow
/// panning a generous margin *past* the content so the canvas feels like
/// something you grab and move (Figma / Miro / Obsidian-canvas style), while
/// still being bounded (not infinite). Pure so it's unit-testable.
public enum CanvasScroll {
    /// Clamp `proposed` clip origin so the canvas pans freely (immediate, 2D,
    /// grab-the-canvas feel) but always keeps at least `keepFraction` of the
    /// content-or-viewport (whichever is smaller) visible on each axis — so the
    /// graph can never be stranded in a corner or lock onto blank space.
    /// Constrains against the content rect (not the padded document frame).
    ///
    /// `keepFraction` is a FRACTION (0…1), not a fixed length: a fixed margin
    /// breaks under zoom/small viewports (when the viewport shrinks below the
    /// margin, nothing stays visible). Proportional keep never collapses to 0.
    public static func constrainedOrigin(
        proposed: CGPoint, viewport: CGSize, content: CGRect, keepFraction: CGFloat
    ) -> CGPoint {
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            min(max(v, lo), max(lo, hi))
        }
        let f = min(max(keepFraction, 0), 1)
        let keepX = min(content.width, viewport.width) * f
        let keepY = min(content.height, viewport.height) * f
        // Visible x-range [origin.x, origin.x+vp] must overlap [content.minX,
        // content.maxX] by ≥ keepX.
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
    /// Fraction of the content (or viewport, whichever is smaller) kept visible
    /// on each axis — you can pan ~40% off for the grab-feel, never lose it.
    static let keepFraction: CGFloat = 0.6

    // Grab-to-pan on the clip's OWN area — the margin around/beyond the document
    // view that the MindMapView doesn't cover. Those pixels belong to the clip
    // (the doc view sits on top), so the canvas's own drag-pan never sees them;
    // without this you "can't drag the non-canvas area".
    private var panStartWindow: NSPoint?
    private var panStartOrigin: NSPoint?

    override func mouseDown(with event: NSEvent) {
        panStartWindow = event.locationInWindow
        panStartOrigin = bounds.origin
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startWindow = panStartWindow, let startOrigin = panStartOrigin else {
            return super.mouseDragged(with: event)
        }
        let dx = event.locationInWindow.x - startWindow.x
        let dy = event.locationInWindow.y - startWindow.y
        // Flipped clip (follows the doc view): drag right → content right →
        // origin.x decreases; matches MindMapView's own drag-pan convention.
        let target = NSPoint(x: startOrigin.x - dx, y: startOrigin.y + dy)
        scroll(to: constrainBoundsRect(NSRect(origin: target, size: bounds.size)).origin)
        enclosingScrollView?.reflectScrolledClipView(self)
    }

    override func mouseUp(with event: NSEvent) {
        if panStartWindow != nil { NSCursor.pop() }
        panStartWindow = nil
        panStartOrigin = nil
    }

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
            keepFraction: Self.keepFraction)
        return NSRect(origin: origin, size: proposedBounds.size)
    }
}
