import AppKit
import KepBase
import KepCore

/// The CSV grid's cell font, resolved from preferences (javamind parity with
/// the CSV editor font setting). Size is clamped so text fits the fixed row
/// height; family falls back to the system font.
public enum CSVFont {
    /// Clamp a requested point size to what the grid row height can show.
    public static func clampSize(_ size: Double) -> CGFloat {
        min(16, max(9, CGFloat(size)))
    }

    /// The resolved cell font from the saved family + size.
    public static func cell() -> NSFont {
        let size = clampSize(PrefKeys.double(PrefKeys.csvFontSize, fallback: 12))
        return EditorFont.resolve(family: PrefKeys.string(PrefKeys.csvFontFamily), size: size)
    }
}

public extension Notification.Name {
    /// Posted when the CSV grid font preference changes.
    static let csvFontChanged = Notification.Name("kep.csvFontChanged")
}
