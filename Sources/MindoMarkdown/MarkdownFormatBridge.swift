import AppKit

/// Bridges global commands (⌘P palette entries) to the focused markdown
/// editor's formatting actions. Formatting wraps/prefixes the live selection,
/// so it must run on the focused `MarkdownDropTextView` — routed through its
/// delegate (the Coordinator) exactly like the ⌘B/⌘I key path, not the
/// model-level snippet append.
public enum MarkdownFormatBridge {

    /// The formatting commands surfaced in the palette. Raw value is the
    /// Coordinator's @objc selector name.
    public enum Command: String, CaseIterable {
        case heading1 = "toolbarHeading1"
        case heading2 = "toolbarHeading2"
        case heading3 = "toolbarHeading3"
        case quote = "toolbarQuote"
        case horizontalRule = "toolbarHorizontalRule"
        case comment = "toolbarComment"
        case table = "toolbarTable"
        case image = "toolbarImage"
    }

    /// Parse + clamp the rows/cols text from the table prompt to 1…20, with
    /// sensible defaults. Pure so the clamping is unit-testable.
    public static func sanitizedTableSize(rows: String, cols: String) -> (rows: Int, cols: Int) {
        func clamp(_ s: String, _ fallback: Int) -> Int {
            max(1, min(20, Int(s.trimmingCharacters(in: .whitespaces)) ?? fallback))
        }
        return (clamp(rows, 2), clamp(cols, 3))
    }

    /// Apply `command` to the focused markdown editor. Returns false (no-op)
    /// when no markdown editor holds focus.
    @discardableResult
    public static func perform(_ command: Command) -> Bool {
        perform(Selector((command.rawValue)))
    }

    @discardableResult
    static func perform(_ selector: Selector) -> Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? MarkdownDropTextView,
              let target = tv.delegate, target.responds(to: selector) else { return false }
        _ = target.perform(selector)
        return true
    }
}
