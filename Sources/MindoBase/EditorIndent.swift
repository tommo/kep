import Foundation

/// Pure-logic transforms for Tab / Shift-Tab indent + outdent shared by
/// the markdown and plantuml editors. Operates on the selected lines as
/// one block so callers can wire NSTextView `insertTab(_:)` /
/// `insertBacktab(_:)` straight through.
public enum EditorIndent {

    /// One indent level. 2 spaces matches the markdown auto-continue-list
    /// output so manually-indented lists render the same as the
    /// auto-extended ones; works fine for plantuml too (the parser
    /// accepts any consistent indent).
    public static let unit: String = "  "

    /// Apply `transform` to every line in `block`. Empty trailing line
    /// (the result of split's empty terminator handling) is preserved so
    /// callers don't accidentally strip a final newline.
    private static func mapLines(_ block: String, _ transform: (String) -> String) -> String {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { transform(String($0)) }.joined(separator: "\n")
    }

    /// Indent every line of `block` by one level (2 spaces).
    public static func indent(_ block: String) -> String {
        mapLines(block) { unit + $0 }
    }

    /// Outdent every line of `block` by one level. Removes either the
    /// indent unit OR a leading tab (whichever's present); lines without
    /// a leading indent stay as-is. Mirrors what most code editors do
    /// when Shift-Tab encounters a non-indented line in a multi-line
    /// selection.
    public static func outdent(_ block: String) -> String {
        mapLines(block) { line in
            if line.hasPrefix(unit) {
                return String(line.dropFirst(unit.count))
            }
            if line.hasPrefix("\t") {
                return String(line.dropFirst())
            }
            return line
        }
    }
}
