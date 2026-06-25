import AppKit

/// Parser/serializer for the per-topic color strings on disk. Mindolph
/// writes them as standard hex strings inside backtick-fenced attributes:
///   `> fillColor=`#7AA3E5`,textColor=`#000000``.
/// JavaFX's Color.toString also produces `0xRRGGBBAA`, so we accept both.
enum MindMapColor {

    /// Parse a hex color string into an `NSColor`. Accepts:
    ///   `#RGB`, `#RRGGBB`, `#RRGGBBAA`,
    ///   `0xRRGGBBAA` (Java's Color.toString output).
    /// Returns nil for anything we can't decode so the caller can fall
    /// back to the theme.
    static func parse(_ raw: String?) -> NSColor? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        else if s.hasPrefix("0x") || s.hasPrefix("0X") { s.removeFirst(2) }
        // Expand #RGB shorthand to #RRGGBB.
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        if hasAlpha {
            r = CGFloat((value >> 24) & 0xFF) / 255.0
            g = CGFloat((value >> 16) & 0xFF) / 255.0
            b = CGFloat((value >> 8)  & 0xFF) / 255.0
            a = CGFloat( value        & 0xFF) / 255.0
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255.0
            g = CGFloat((value >> 8)  & 0xFF) / 255.0
            b = CGFloat( value        & 0xFF) / 255.0
            a = 1.0
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// Serialize an `NSColor` to the on-disk `#RRGGBB` form (or `#RRGGBBAA`
    /// when alpha < 1) so a round-trip with javamind stays lossless.
    static func write(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(rgb.redComponent   * 255)) & 0xFF
        let g = Int(round(rgb.greenComponent * 255)) & 0xFF
        let b = Int(round(rgb.blueComponent  * 255)) & 0xFF
        let a = Int(round(rgb.alphaComponent * 255)) & 0xFF
        if a == 0xFF {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
