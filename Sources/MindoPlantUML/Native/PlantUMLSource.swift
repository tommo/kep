import Foundation

/// Source-text lookups for the interactive preview: given an entity name shown
/// in the diagram, find where it lives in the PlantUML source so a click can
/// jump there. Pure → unit-testable; ranges are UTF-16 (NSTextView-ready).
public enum PlantUMLSource {
    /// First occurrence of `entity` in `source`, preferring a quoted
    /// `"entity"` (aliased participant declaration), then a whole-word match,
    /// then any substring. nil when absent/empty.
    public static func firstRange(ofEntity entity: String, in source: String) -> NSRange? {
        let name = entity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let ns = source as NSString

        let quoted = ns.range(of: "\"\(name)\"")
        if quoted.location != NSNotFound { return quoted }

        let escaped = NSRegularExpression.escapedPattern(for: name)
        if let re = try? NSRegularExpression(pattern: "(?<!\\w)\(escaped)(?!\\w)"),
           let m = re.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)),
           m.range.location != NSNotFound {
            return m.range
        }

        let plain = ns.range(of: name)
        return plain.location == NSNotFound ? nil : plain
    }
}
