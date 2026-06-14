import CoreGraphics

/// Pure coordinate math for the mindmap minimap overlay. Maps between document
/// space (where topic frames + the scroll viewport live) and the small minimap
/// rectangle, aspect-fitting a "world" rect (the union of the content bounds and
/// the current viewport) into the minimap so both the whole map and the visible
/// region are always representable. Lives apart from the NSView so the mapping
/// is unit-testable without AppKit.
public struct MinimapTransform: Equatable {
    /// Uniform document→minimap scale (minimap is always ≤ 1:1, usually ≪).
    public let scale: CGFloat
    /// The document-space region the minimap depicts (content ∪ viewport).
    public let world: CGRect
    /// Where `world` lands inside the minimap's own bounds (centered, padded).
    public let fitted: CGRect

    /// Aspect-fit `world` into a minimap of `area` size, leaving `padding` on
    /// every edge. Both spaces are top-left-origin (the canvas + minimap are
    /// both flipped), so no axis inversion is needed.
    public init(world: CGRect, area: CGSize, padding: CGFloat = 6) {
        let availW = max(1, area.width - 2 * padding)
        let availH = max(1, area.height - 2 * padding)
        let s: CGFloat
        if world.width > 0, world.height > 0 {
            s = min(availW / world.width, availH / world.height)
        } else {
            s = 1
        }
        self.scale = s
        self.world = world
        let w = world.width * s
        let h = world.height * s
        self.fitted = CGRect(x: (area.width - w) / 2, y: (area.height - h) / 2, width: w, height: h)
    }

    /// Project a document-space rect (topic frame, viewport) into minimap space.
    public func project(_ rect: CGRect) -> CGRect {
        CGRect(
            x: fitted.minX + (rect.minX - world.minX) * scale,
            y: fitted.minY + (rect.minY - world.minY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// Inverse-map a minimap-space point back to document space — used to turn
    /// a click in the minimap into a scroll target.
    public func unproject(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: world.minX + (point.x - fitted.minX) / scale,
            y: world.minY + (point.y - fitted.minY) / scale
        )
    }
}

public enum MinimapGeometry {
    /// The scroll origin (top-left, document coords) that centers `docPoint`
    /// in a viewport of `viewportSize`, clamped so it never scrolls past the
    /// `scrollable` content extent. Used when the user clicks the minimap.
    public static func centeredOrigin(
        on docPoint: CGPoint,
        viewportSize: CGSize,
        scrollable: CGSize
    ) -> CGPoint {
        let rawX = docPoint.x - viewportSize.width / 2
        let rawY = docPoint.y - viewportSize.height / 2
        let maxX = max(0, scrollable.width - viewportSize.width)
        let maxY = max(0, scrollable.height - viewportSize.height)
        return CGPoint(
            x: min(max(0, rawX), maxX),
            y: min(max(0, rawY), maxY)
        )
    }
}
