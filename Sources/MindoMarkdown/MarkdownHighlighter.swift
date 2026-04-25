import AppKit
import Foundation

/// Regex-based syntax highlighter for the Markdown code-area pane.
/// Patterns mirror `MarkdownConstants` from `mindolph-base` (HEADING / BOLD /
/// ITALIC / CODE / CODE_BLOCK / LIST / URL / QUOTE / HORIZONTAL_RULE).
public final class MarkdownHighlighter {
    public struct Style {
        public let color: NSColor
        public let bold: Bool
        public let italic: Bool
        public let monospace: Bool
        public init(color: NSColor, bold: Bool = false, italic: Bool = false, monospace: Bool = false) {
            self.color = color; self.bold = bold; self.italic = italic; self.monospace = monospace
        }
    }

    public struct Theme {
        public var heading: Style
        public var bold: Style
        public var italic: Style
        public var code: Style
        public var codeBlock: Style
        public var quote: Style
        public var url: Style
        public var list: Style
        public var horizontalRule: Style
        public var defaultStyle: Style

        public static let light = Theme(
            heading: Style(color: NSColor(red: 0.10, green: 0.36, blue: 0.66, alpha: 1), bold: true),
            bold: Style(color: NSColor(white: 0.10, alpha: 1), bold: true),
            italic: Style(color: NSColor(white: 0.10, alpha: 1), italic: true),
            code: Style(color: NSColor(red: 0.55, green: 0.18, blue: 0.40, alpha: 1), monospace: true),
            codeBlock: Style(color: NSColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1), monospace: true),
            quote: Style(color: NSColor(red: 0.40, green: 0.40, blue: 0.42, alpha: 1), italic: true),
            url: Style(color: NSColor(red: 0.05, green: 0.42, blue: 0.85, alpha: 1)),
            list: Style(color: NSColor(red: 0.20, green: 0.50, blue: 0.20, alpha: 1), bold: true),
            horizontalRule: Style(color: NSColor(white: 0.50, alpha: 1)),
            defaultStyle: Style(color: NSColor(white: 0.10, alpha: 1))
        )

        public static let dark = Theme(
            heading: Style(color: NSColor(red: 0.45, green: 0.74, blue: 1.00, alpha: 1), bold: true),
            bold: Style(color: NSColor(white: 0.95, alpha: 1), bold: true),
            italic: Style(color: NSColor(white: 0.95, alpha: 1), italic: true),
            code: Style(color: NSColor(red: 1.00, green: 0.65, blue: 0.85, alpha: 1), monospace: true),
            codeBlock: Style(color: NSColor(white: 0.85, alpha: 1), monospace: true),
            quote: Style(color: NSColor(white: 0.65, alpha: 1), italic: true),
            url: Style(color: NSColor(red: 0.42, green: 0.78, blue: 1.00, alpha: 1)),
            list: Style(color: NSColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 1), bold: true),
            horizontalRule: Style(color: NSColor(white: 0.55, alpha: 1)),
            defaultStyle: Style(color: NSColor(white: 0.92, alpha: 1))
        )
    }

    public var theme: Theme
    public var baseFont: NSFont

    public init(theme: Theme = .light, baseFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)) {
        self.theme = theme
        self.baseFont = baseFont
    }

    /// Patterns (compiled lazily) — order matters: outer matches (code blocks,
    /// headings) win over inline (`code`, `*bold*`).
    private static let codeBlock = MarkdownHighlighter.regex(#"(?m)^[ ]{0,3}`{3}[\s\S]*?`{3}"#)
    private static let heading   = MarkdownHighlighter.regex(#"(?m)^#{1,6}[ ]+.*$"#)
    private static let quote     = MarkdownHighlighter.regex(#"(?m)^[ ]{0,3}>.*$"#)
    private static let list      = MarkdownHighlighter.regex(#"(?m)^[ ]*((\*|\+|-)[ ]+|\d+\.[ ]+)"#)
    private static let hr        = MarkdownHighlighter.regex(#"(?m)^([-*_])[ ]*(\1[ ]*){2,}$"#)
    private static let bold      = MarkdownHighlighter.regex(#"(\*\*|__)(?=\S)([^*_]+?)(?<=\S)\1"#)
    private static let italic    = MarkdownHighlighter.regex(#"(?<![*_])(\*|_)(?=\S)([^*_]+?)(?<=\S)\1(?![*_])"#)
    private static let code      = MarkdownHighlighter.regex(#"`[^`\n]+`"#)
    private static let url       = MarkdownHighlighter.regex(#"!?\[[^\]\n]*\](\([^)\n]*\))?"#)

    private static func regex(_ p: String) -> NSRegularExpression {
        return try! NSRegularExpression(pattern: p, options: [])
    }

    /// Apply highlighting to `storage` for the given range. Removes existing color
    /// attributes first, then layers in span attributes.
    public func highlight(_ storage: NSTextStorage, range: NSRange? = nil) {
        let full = NSRange(location: 0, length: storage.length)
        let r = range ?? full
        guard r.length > 0 else { return }

        storage.beginEditing()
        // Reset to default style.
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: theme.defaultStyle.color,
        ], range: r)

        let text = storage.string

        apply(Self.codeBlock, in: text, range: r, storage: storage, style: theme.codeBlock)
        apply(Self.heading,   in: text, range: r, storage: storage, style: theme.heading)
        apply(Self.quote,     in: text, range: r, storage: storage, style: theme.quote)
        apply(Self.hr,        in: text, range: r, storage: storage, style: theme.horizontalRule)
        apply(Self.list,      in: text, range: r, storage: storage, style: theme.list)
        apply(Self.bold,      in: text, range: r, storage: storage, style: theme.bold)
        apply(Self.italic,    in: text, range: r, storage: storage, style: theme.italic)
        apply(Self.code,      in: text, range: r, storage: storage, style: theme.code)
        apply(Self.url,       in: text, range: r, storage: storage, style: theme.url)

        storage.endEditing()
    }

    private func apply(
        _ regex: NSRegularExpression,
        in text: String,
        range: NSRange,
        storage: NSTextStorage,
        style: Style
    ) {
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: style.color]
            attrs[.font] = font(for: style)
            storage.addAttributes(attrs, range: r)
        }
    }

    private func font(for style: Style) -> NSFont {
        let pt = baseFont.pointSize
        if style.monospace {
            return NSFont.monospacedSystemFont(ofSize: pt, weight: .regular)
        }
        var traits: NSFontTraitMask = []
        if style.bold { traits.insert(.boldFontMask) }
        if style.italic { traits.insert(.italicFontMask) }
        if !traits.isEmpty {
            return NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
        }
        return baseFont
    }
}
