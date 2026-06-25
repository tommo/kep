import CoreGraphics

/// Pure edge-proximity auto-scroll math for dragging a topic toward an
/// off-screen target. When the drag cursor comes within `margin` of a
/// viewport edge it returns a scroll delta whose speed ramps up the closer
/// the cursor gets to (or past) the edge. Table/AppKit-free so the ramp and
/// the per-edge selection are unit-testable.
public enum MindMapAutoScroll {

    /// Scroll delta to apply this drag tick. `point` and `visibleRect` share
    /// the document view's (flipped) coordinate space: +dy scrolls toward
    /// larger y (down), -dy up. `.zero` when the cursor is comfortably inside.
    public static func delta(point: CGPoint, visibleRect: CGRect,
                             margin: CGFloat, maxSpeed: CGFloat) -> CGVector {
        guard margin > 0, !visibleRect.isEmpty else { return .zero }
        var dx: CGFloat = 0
        var dy: CGFloat = 0

        let leftDist = point.x - visibleRect.minX
        let rightDist = visibleRect.maxX - point.x
        if leftDist < margin {
            dx = -speed(forDistance: leftDist, margin: margin, maxSpeed: maxSpeed)
        } else if rightDist < margin {
            dx = speed(forDistance: rightDist, margin: margin, maxSpeed: maxSpeed)
        }

        let topDist = point.y - visibleRect.minY
        let bottomDist = visibleRect.maxY - point.y
        if topDist < margin {
            dy = -speed(forDistance: topDist, margin: margin, maxSpeed: maxSpeed)
        } else if bottomDist < margin {
            dy = speed(forDistance: bottomDist, margin: margin, maxSpeed: maxSpeed)
        }

        return CGVector(dx: dx, dy: dy)
    }

    /// 0 at the inner edge of the margin band, ramping to `maxSpeed` at the
    /// boundary and staying at `maxSpeed` once the cursor is past it
    /// (negative distance).
    private static func speed(forDistance d: CGFloat, margin: CGFloat, maxSpeed: CGFloat) -> CGFloat {
        if d <= 0 { return maxSpeed }
        let t = 1 - (d / margin)        // d == margin → 0, d → 0 → 1
        return maxSpeed * max(0, min(1, t))
    }
}
