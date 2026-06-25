import CoreGraphics

/// Topic border stroke width — same shape as the corner-radius
/// resolver. Pure-logic clamp so the unit-test suite can pin the
/// behavior independent of the draw path.
public enum MindMapBorderWidth {

    public static let defaultWidth: CGFloat = 1.0
    public static let maxWidth: CGFloat = 8.0

    /// `pref` is the raw `PrefKeys.mindmapBorderWidth` value (0 = unset).
    /// Returns `defaultWidth` for 0 / negative / non-finite input;
    /// otherwise clamps positive values into `(0, maxWidth]`.
    public static func resolve(pref: Double) -> CGFloat {
        let v = CGFloat(pref)
        guard v.isFinite, v > 0 else { return defaultWidth }
        return min(v, maxWidth)
    }
}

/// Resolve the topic corner radius respecting the user override.
/// Mindolph parity (`spnRoundRadius`): the user picks a value in
/// Preferences; an unset/zero pref means "fall back to the theme's
/// value". Clamped to `[0, 32]` so a runaway pref can't render
/// circles.
public enum MindMapCornerRadius {

    public static let maxRadius: CGFloat = 32

    /// `pref` is the raw `PrefKeys.mindmapCornerRadius` value (0 = unset);
    /// `themeDefault` is the active theme's `cornerRadius`.
    public static func resolve(pref: Double, themeDefault: CGFloat) -> CGFloat {
        let v = CGFloat(pref)
        guard v.isFinite, v > 0 else { return themeDefault }
        return min(max(v, 0), maxRadius)
    }
}

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
