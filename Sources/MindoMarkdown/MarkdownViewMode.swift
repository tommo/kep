import Foundation

/// Which panes the markdown editor shows. Mirrors Obsidian's editor /
/// reading / split views and mindolph's preview toggle. Kept as pure data
/// (no AppKit) so the visibility rules and cycling are unit-testable; the
/// editor view reads `showsEditor` / `showsPreview` to hide/show its panes.
public enum MarkdownViewMode: String, CaseIterable, Sendable {
    /// Source editor only (Obsidian "editing" view).
    case editor
    /// Source + rendered preview side by side (the default).
    case split
    /// Rendered preview only (Obsidian "reading" view).
    case preview

    public var showsEditor: Bool { self != .preview }
    public var showsPreview: Bool { self != .editor }

    /// SF Symbol used for this mode's toolbar segment.
    public var symbolName: String {
        switch self {
        case .editor:  return "pencil"
        case .split:   return "rectangle.split.2x1"
        case .preview: return "eye"
        }
    }

    /// Toolbar tooltip. Plain English to match the other markdown toolbar
    /// buttons, which are hardcoded (the `L()` localization helper lives in
    /// the app target, not this module).
    public var tooltip: String {
        switch self {
        case .editor:  return "Editor only"
        case .split:   return "Editor & preview"
        case .preview: return "Preview only"
        }
    }

    /// Next mode in the editor → split → preview → editor cycle. Lets a
    /// single keyboard shortcut rotate through the modes.
    public func next() -> MarkdownViewMode {
        let all = MarkdownViewMode.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }

    /// Parse a persisted raw value, falling back to `.editor` for unknown /
    /// missing values — the single live-styled pane is the modern default
    /// (the HTML side-by-side preview is opt-in via the footer switch).
    public static func from(rawValue raw: String?) -> MarkdownViewMode {
        guard let raw, let mode = MarkdownViewMode(rawValue: raw) else { return .editor }
        return mode
    }
}
