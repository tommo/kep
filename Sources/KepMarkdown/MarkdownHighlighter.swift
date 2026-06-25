import AppKit
import Foundation
import KepBase

/// Live-styling Markdown renderer for the single-pane editor (Obsidian "Live
/// Preview" flavour, on TextKit): headings are sized by level, emphasis is
/// rendered with real bold/italic/mono fonts, and the markup characters
/// (`#`, `**`, `` ` ``, `>`, …) are de-emphasised — fully revealed only on the
/// paragraph the cursor is in, dimmed everywhere else so the prose stands out.
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
        public var marker: NSColor   // dimmed markup punctuation

        public static let light = make(palette: .light,
            list: NSColor(red: 0.20, green: 0.50, blue: 0.20, alpha: 1),
            horizontalRule: NSColor(white: 0.50, alpha: 1),
            marker: NSColor(white: 0.66, alpha: 1))

        public static let dark = make(palette: .dark,
            list: NSColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 1),
            horizontalRule: NSColor(white: 0.55, alpha: 1),
            marker: NSColor(white: 0.45, alpha: 1))

        /// The effective theme for the appearance — built from the *resolved*
        /// palette so the user's custom editor colors apply. Editors call this
        /// (not the static light/dark) so re-highlighting picks up changes.
        public static func resolved(dark: Bool) -> Theme {
            make(palette: .resolved(dark: dark),
                 list: dark ? NSColor(red: 0.55, green: 0.85, blue: 0.55, alpha: 1)
                            : NSColor(red: 0.20, green: 0.50, blue: 0.20, alpha: 1),
                 horizontalRule: dark ? NSColor(white: 0.55, alpha: 1) : NSColor(white: 0.50, alpha: 1),
                 marker: dark ? NSColor(white: 0.45, alpha: 1) : NSColor(white: 0.66, alpha: 1))
        }

        /// Build a theme from the shared [SyntaxPalette] for the common roles,
        /// plus the markdown-specific colors (list / rule / dim marker) that
        /// have no palette equivalent.
        static func make(palette p: SyntaxPalette, list: NSColor,
                         horizontalRule: NSColor, marker: NSColor) -> Theme {
            Theme(
                heading: Style(color: p.keyword, bold: true),
                bold: Style(color: p.text, bold: true),
                italic: Style(color: p.text, italic: true),
                code: Style(color: p.string, monospace: true),
                codeBlock: Style(color: p.punctuation, monospace: true),
                quote: Style(color: p.comment, italic: true),
                url: Style(color: p.link),
                list: Style(color: list, bold: true),
                horizontalRule: Style(color: horizontalRule),
                defaultStyle: Style(color: p.text),
                marker: marker
            )
        }
    }

    /// Heading point-size multipliers, H1…H6.
    private static let headingScale: [CGFloat] = [1.7, 1.45, 1.28, 1.15, 1.07, 1.0]

    public var theme: Theme
    public var baseFont: NSFont

    public init(theme: Theme = .light, baseFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)) {
        self.theme = theme
        self.baseFont = baseFont
    }

    // MARK: - Font cache

    // The highlight passes used to build a font per match — `mono(...)`,
    // `NSFontManager.convert(...)`, `systemFont(ofSize:)` — on *every* bold,
    // italic, heading and code span, on every keystroke. Font construction is
    // the dominant cost of a pass, so cache the fixed set keyed on the only
    // thing they depend on (the base point size) and rebuild only when it
    // changes.
    private var cachedPointSize: CGFloat = -1
    private var _mono: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    private var _bold: NSFont = .boldSystemFont(ofSize: 13)
    private var _italic: NSFont = .systemFont(ofSize: 13)
    private var _boldItalic: NSFont = .boldSystemFont(ofSize: 13)
    private var _headings: [NSFont] = []

    private func ensureFontCache() {
        let ps = baseFont.pointSize
        if ps == cachedPointSize, !_headings.isEmpty { return }
        cachedPointSize = ps
        let fm = NSFontManager.shared
        _mono = NSFont.monospacedSystemFont(ofSize: ps, weight: .regular)
        _bold = fm.convert(baseFont, toHaveTrait: .boldFontMask)
        _italic = fm.convert(baseFont, toHaveTrait: .italicFontMask)
        _boldItalic = fm.convert(_bold, toHaveTrait: .italicFontMask)
        _headings = Self.headingScale.map {
            fm.convert(.systemFont(ofSize: ps * $0, weight: .bold), toHaveTrait: .boldFontMask)
        }
    }

    private static func regex(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: []) }

    // Capturing groups split markup punctuation from content so the punctuation
    // can be dimmed independently.
    private static let codeBlock = regex(#"(?m)^[ ]{0,3}`{3}[\s\S]*?`{3}"#)
    private static let heading   = regex(#"(?m)^(#{1,6})([ ]+)(.*)$"#)        // 1=#s 2=space 3=text
    private static let quote     = regex(#"(?m)^([ ]{0,3}>[ ]?)(.*)$"#)       // 1=marker 2=text
    private static let list      = regex(#"(?m)^([ ]*)((?:\*|\+|-)[ ]+|\d+\.[ ]+)"#)  // 2=bullet
    private static let hr        = regex(#"(?m)^([-*_])[ ]*(\1[ ]*){2,}$"#)
    private static let bold      = regex(#"(\*\*|__)(?=\S)([^*_]+?)(?<=\S)\1"#)        // 1=marker 2=content
    private static let italic    = regex(#"(?<![*_])(\*|_)(?=\S)([^*_]+?)(?<=\S)\1(?![*_])"#)
    private static let code      = regex(#"(`)([^`\n]+)(`)"#)
    private static let url       = regex(#"!?\[[^\]\n]*\](\([^)\n]*\))?"#)
    private static let wikiLink  = regex(#"\[\[[^\]\n]+\]\]"#)   // [[Target]] — both brackets

    /// Apply live styling to the whole `storage`. `activeRange` is the editor's
    /// current selection — markup on the paragraph(s) it touches is shown in
    /// full; elsewhere the punctuation is dimmed.
    public func highlight(_ storage: NSTextStorage, activeRange: NSRange? = nil) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let text = storage.string as NSString
        let activePara = activeRange.map { text.paragraphRange(for: $0) }
        ensureFontCache()

        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: theme.defaultStyle.color], range: full)

        // Block elements first.
        enumerate(Self.codeBlock, text) { m in
            storage.addAttributes([.font: _mono, .foregroundColor: theme.codeBlock.color], range: m.range)
        }
        enumerate(Self.heading, text) { m in
            let level = max(1, min(6, m.range(at: 1).length))
            let hFont = _headings[level - 1]
            storage.addAttributes([.font: hFont, .foregroundColor: theme.heading.color], range: m.range(at: 3))
            markup(m.range(at: 1), m.range(at: 2), in: storage, activePara: activePara, revealFont: hFont)
        }
        enumerate(Self.quote, text) { m in
            storage.addAttributes([.font: font(theme.quote), .foregroundColor: theme.quote.color], range: m.range(at: 2))
            markup(m.range(at: 1), in: storage, activePara: activePara)
        }
        enumerate(Self.hr, text) { m in
            storage.addAttributes([.foregroundColor: theme.horizontalRule.color], range: m.range)
        }
        enumerate(Self.list, text) { m in
            storage.addAttributes([.foregroundColor: theme.list.color, .font: font(theme.list)], range: m.range(at: 2))
        }
        // Inline spans.
        enumerate(Self.bold, text) { m in styleSpan(m, content: 2, in: storage, style: theme.bold, activePara: activePara) }
        enumerate(Self.italic, text) { m in styleSpan(m, content: 2, in: storage, style: theme.italic, activePara: activePara) }
        enumerate(Self.code, text) { m in
            storage.addAttributes([.font: _mono, .foregroundColor: theme.code.color], range: m.range(at: 2))
            markup(m.range(at: 1), m.range(at: 3), in: storage, activePara: activePara)
        }
        enumerate(Self.url, text) { m in
            storage.addAttributes([.foregroundColor: theme.url.color], range: m.range)
        }
        // After the generic link rule, which matches only the inner [..] of a
        // [[wiki link]] and leaves the trailing ] uncolored — color the whole thing.
        enumerate(Self.wikiLink, text) { m in
            storage.addAttributes([.foregroundColor: theme.url.color], range: m.range)
        }
        storage.endEditing()
    }

    // MARK: - Helpers

    private func enumerate(_ re: NSRegularExpression, _ text: NSString, _ body: (NSTextCheckingResult) -> Void) {
        re.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { m, _, _ in
            if let m { body(m) }
        }
    }

    /// Style an emphasis span: its content gets the style; the leading marker
    /// (group 1) and the equal-length trailing marker are dimmed off the active
    /// paragraph.
    private func styleSpan(_ m: NSTextCheckingResult, content: Int, in storage: NSTextStorage,
                           style: Style, activePara: NSRange?) {
        storage.addAttributes([.font: font(style), .foregroundColor: style.color], range: m.range(at: content))
        let open = m.range(at: 1)
        let close = NSRange(location: m.range.location + m.range.length - open.length, length: open.length)
        markup(open, close, in: storage, activePara: activePara)
    }

    /// Dim one or two markup ranges, unless they're on the active paragraph.
    private func markup(_ ranges: NSRange..., in storage: NSTextStorage, activePara: NSRange?, revealFont: NSFont? = nil) {
        for r in ranges where r.length > 0 {
            let onActive = activePara.map { NSIntersectionRange($0, r).length > 0 } ?? false
            if onActive {
                // Revealed: keep it readable (match heading font if given).
                if let revealFont { storage.addAttributes([.font: revealFont], range: r) }
            } else {
                storage.addAttributes([.foregroundColor: theme.marker], range: r)
            }
        }
    }

    private func font(_ style: Style) -> NSFont {
        if style.monospace { return _mono }
        switch (style.bold, style.italic) {
        case (true, true):   return _boldItalic
        case (true, false):  return _bold
        case (false, true):  return _italic
        case (false, false): return baseFont
        }
    }
}
