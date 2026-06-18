import AppKit
import Foundation

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
            defaultStyle: Style(color: NSColor(white: 0.10, alpha: 1)),
            marker: NSColor(white: 0.66, alpha: 1)
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
            defaultStyle: Style(color: NSColor(white: 0.92, alpha: 1)),
            marker: NSColor(white: 0.45, alpha: 1)
        )
    }

    /// Heading point-size multipliers, H1…H6.
    private static let headingScale: [CGFloat] = [1.7, 1.45, 1.28, 1.15, 1.07, 1.0]

    public var theme: Theme
    public var baseFont: NSFont

    public init(theme: Theme = .light, baseFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)) {
        self.theme = theme
        self.baseFont = baseFont
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

    /// Apply live styling to the whole `storage`. `activeRange` is the editor's
    /// current selection — markup on the paragraph(s) it touches is shown in
    /// full; elsewhere the punctuation is dimmed.
    public func highlight(_ storage: NSTextStorage, activeRange: NSRange? = nil) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let text = storage.string as NSString
        let activePara = activeRange.map { text.paragraphRange(for: $0) }

        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: theme.defaultStyle.color], range: full)

        // Block elements first.
        enumerate(Self.codeBlock, text) { m in
            storage.addAttributes([.font: mono(baseFont.pointSize), .foregroundColor: theme.codeBlock.color], range: m.range)
        }
        enumerate(Self.heading, text) { m in
            let level = max(1, min(6, m.range(at: 1).length))
            let size = baseFont.pointSize * Self.headingScale[level - 1]
            let hFont = NSFontManager.shared.convert(.systemFont(ofSize: size, weight: .bold), toHaveTrait: .boldFontMask)
            storage.addAttributes([.font: hFont, .foregroundColor: theme.heading.color], range: m.range(at: 3))
            markup(m.range(at: 1), m.range(at: 2), in: storage, activePara: activePara, sizedTo: size)
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
            storage.addAttributes([.font: mono(baseFont.pointSize), .foregroundColor: theme.code.color], range: m.range(at: 2))
            markup(m.range(at: 1), m.range(at: 3), in: storage, activePara: activePara)
        }
        enumerate(Self.url, text) { m in
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
    private func markup(_ ranges: NSRange..., in storage: NSTextStorage, activePara: NSRange?, sizedTo: CGFloat? = nil) {
        for r in ranges where r.length > 0 {
            let onActive = activePara.map { NSIntersectionRange($0, r).length > 0 } ?? false
            if onActive {
                // Revealed: keep it readable (match heading size if given).
                if let sz = sizedTo { storage.addAttributes([.font: NSFont.systemFont(ofSize: sz, weight: .bold)], range: r) }
            } else {
                storage.addAttributes([.foregroundColor: theme.marker], range: r)
            }
        }
    }

    private func mono(_ pt: CGFloat) -> NSFont { NSFont.monospacedSystemFont(ofSize: pt, weight: .regular) }

    private func font(_ style: Style) -> NSFont {
        if style.monospace { return mono(baseFont.pointSize) }
        var traits: NSFontTraitMask = []
        if style.bold { traits.insert(.boldFontMask) }
        if style.italic { traits.insert(.italicFontMask) }
        return traits.isEmpty ? baseFont : NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
    }
}
