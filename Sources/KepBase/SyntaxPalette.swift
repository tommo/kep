import AppKit

/// The shared source of truth for editor syntax-highlight colors, so the
/// markdown and PlantUML editors (and any future CSV/code editor) draw their
/// common token roles from one place instead of each hardcoding near-identical
/// light/dark constants. Resolved by appearance; a future custom-theme layer
/// overrides these values once and every editor follows.
public struct SyntaxPalette: Sendable {
    /// Default body text.
    public var text: NSColor
    /// Accent for keywords / headings.
    public var keyword: NSColor
    /// Strings / inline code.
    public var string: NSColor
    /// Comments / block quotes.
    public var comment: NSColor
    /// Hyperlinks.
    public var link: NSColor
    /// Secondary punctuation (brackets, fenced-code text).
    public var punctuation: NSColor

    public init(text: NSColor, keyword: NSColor, string: NSColor,
                comment: NSColor, link: NSColor, punctuation: NSColor) {
        self.text = text
        self.keyword = keyword
        self.string = string
        self.comment = comment
        self.link = link
        self.punctuation = punctuation
    }

    public static let light = SyntaxPalette(
        text:        NSColor(white: 0.10, alpha: 1),
        keyword:     NSColor(red: 0.10, green: 0.36, blue: 0.66, alpha: 1),
        string:      NSColor(red: 0.55, green: 0.18, blue: 0.40, alpha: 1),
        comment:     NSColor(red: 0.40, green: 0.40, blue: 0.42, alpha: 1),
        link:        NSColor(red: 0.05, green: 0.42, blue: 0.85, alpha: 1),
        punctuation: NSColor(white: 0.30, alpha: 1)
    )

    public static let dark = SyntaxPalette(
        text:        NSColor(white: 0.92, alpha: 1),
        keyword:     NSColor(red: 0.45, green: 0.74, blue: 1.00, alpha: 1),
        string:      NSColor(red: 1.00, green: 0.65, blue: 0.85, alpha: 1),
        comment:     NSColor(white: 0.65, alpha: 1),
        link:        NSColor(red: 0.42, green: 0.78, blue: 1.00, alpha: 1),
        punctuation: NSColor(white: 0.85, alpha: 1)
    )

    /// The effective palette for the appearance: the built-in base with the
    /// user's custom overrides applied on top (when their custom theme is on).
    public static func resolved(dark: Bool) -> SyntaxPalette {
        let base = dark ? Self.dark : Self.light
        let theme = EditorThemeStore.current
        guard theme.enabled else { return base }
        return base.applying(dark ? theme.dark : theme.light)
    }
}
