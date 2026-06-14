import CoreGraphics

/// Pure geometry for marquee (rubber-band) area selection: the normalized
/// drag rectangle and which element frames it catches. Table/AppKit-free so
/// the enclosure rule is unit-testable on plain CGRects.
public enum MindMapAreaSelection {

    /// Normalized rect spanning two drag points, regardless of drag direction.
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// Items whose frame is caught by `rect`. A frame counts when it
    /// intersects the rect (touch-to-select, like most canvas apps) — pass
    /// `fullyContained: true` to require the frame be entirely inside.
    public static func enclosed<T>(
        _ items: [T],
        frame: (T) -> CGRect,
        in rect: CGRect,
        fullyContained: Bool = false
    ) -> [T] {
        items.filter { item in
            let f = frame(item)
            return fullyContained ? rect.contains(f) : rect.intersects(f)
        }
    }
}
