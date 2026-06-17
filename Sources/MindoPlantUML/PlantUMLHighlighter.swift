import AppKit
import Foundation

/// Lightweight syntax highlighter for PlantUML code areas. Doesn't attempt
/// full grammar — recognizes the most common keywords, comments, strings,
/// brackets, and arrows.
public final class PlantUMLHighlighter {
    public struct Theme {
        public var keyword: NSColor
        public var comment: NSColor
        public var string: NSColor
        public var arrow: NSColor
        public var bracket: NSColor
        public var defaultColor: NSColor

        public static let light = Theme(
            keyword: NSColor(red: 0.10, green: 0.30, blue: 0.65, alpha: 1),
            comment: NSColor(white: 0.45, alpha: 1),
            string: NSColor(red: 0.55, green: 0.20, blue: 0.40, alpha: 1),
            arrow: NSColor(red: 0.75, green: 0.40, blue: 0.10, alpha: 1),
            bracket: NSColor(white: 0.30, alpha: 1),
            defaultColor: NSColor(white: 0.10, alpha: 1)
        )
        public static let dark = Theme(
            keyword: NSColor(red: 0.50, green: 0.75, blue: 1.00, alpha: 1),
            comment: NSColor(white: 0.55, alpha: 1),
            string: NSColor(red: 1.00, green: 0.70, blue: 0.85, alpha: 1),
            arrow: NSColor(red: 1.00, green: 0.75, blue: 0.45, alpha: 1),
            bracket: NSColor(white: 0.85, alpha: 1),
            defaultColor: NSColor(white: 0.92, alpha: 1)
        )
    }

    public var theme: Theme
    public var baseFont: NSFont

    public init(theme: Theme = .light, baseFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)) {
        self.theme = theme
        self.baseFont = baseFont
    }

    // Driven by PlantUMLCatalog so highlighting tracks the same vocabulary as
    // autocompletion (was a stale hardcoded subset).
    private static let keyword = regex(PlantUMLCatalog.keywordRegexPattern)
    private static let comment = regex(#"(?m)('.*$)"#)
    private static let multilineComment = regex(#"/'[\s\S]*?'/"#)
    private static let string  = regex(#"\"[^\"\n]*\""#)
    private static let arrow   = regex(#"(-+(\[.*?\])?(o|\\|/|>|<|\*)?-*(>|<|o|\*|\|>)?|<\.\.|<--|-->|\.\.>)"#)
    private static let bracket = regex(#"[\(\)\[\]\{\}]"#)

    private static func regex(_ p: String) -> NSRegularExpression {
        return try! NSRegularExpression(pattern: p, options: [])
    }

    public func highlight(_ storage: NSTextStorage, range: NSRange? = nil) {
        let full = NSRange(location: 0, length: storage.length)
        let r = range ?? full
        guard r.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: theme.defaultColor], range: r)

        let text = storage.string
        apply(Self.keyword, in: text, range: r, storage: storage, color: theme.keyword, bold: true)
        apply(Self.arrow, in: text, range: r, storage: storage, color: theme.arrow)
        apply(Self.bracket, in: text, range: r, storage: storage, color: theme.bracket)
        apply(Self.string, in: text, range: r, storage: storage, color: theme.string)
        apply(Self.multilineComment, in: text, range: r, storage: storage, color: theme.comment, italic: true)
        apply(Self.comment, in: text, range: r, storage: storage, color: theme.comment, italic: true)

        storage.endEditing()
    }

    private func apply(_ regex: NSRegularExpression, in text: String, range: NSRange, storage: NSTextStorage, color: NSColor, bold: Bool = false, italic: Bool = false) {
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            var traits: NSFontTraitMask = []
            if bold { traits.insert(.boldFontMask) }
            if italic { traits.insert(.italicFontMask) }
            if !traits.isEmpty {
                attrs[.font] = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
            }
            storage.addAttributes(attrs, range: r)
        }
    }
}
