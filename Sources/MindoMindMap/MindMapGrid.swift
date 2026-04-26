import CoreGraphics

/// Pure-logic helpers for the optional canvas grid. Lives here so the
/// step normalization is unit-testable without an NSView fixture.
public enum MindMapGrid {

    /// Lower bound — under 4pt the dots merge into a smear at default
    /// zoom and don't read as a grid. Anything below this snaps up.
    public static let minStep: CGFloat = 4

    /// Upper bound — past 256pt the grid starts to look like decoration
    /// rather than guidance, and the user can just turn it off.
    public static let maxStep: CGFloat = 256

    /// Clamp a raw preference value into a sensible range. Returns 0
    /// for clearly invalid input (negative / NaN / non-finite) so the
    /// caller can early-out and skip drawing entirely.
    public static func normalizedStep(_ raw: Double) -> CGFloat {
        let v = CGFloat(raw)
        guard v.isFinite, v > 0 else { return 0 }
        return min(max(v, minStep), maxStep)
    }
}
