import AppKit

/// Lightweight Lua syntax highlighter for the notebook code cells (and any other
/// Lua editor). Regex-based over the NSTextStorage's UTF-16 ranges, drawing
/// token colors from the shared `SyntaxPalette` so it matches the markdown /
/// PlantUML editors and any custom theme.
///
/// Application order matters — later passes win on overlap: numbers → keywords →
/// strings → comments, so a keyword inside a string is string-colored and a
/// string/keyword inside a comment is comment-colored. (Known regex limitation:
/// a literal `--` *inside* a string is mis-read as a line comment — rare in
/// practice and not worth a full lexer here.)
public enum LuaHighlighter {

    private static let keyword = re(#"\b(and|break|do|else|elseif|end|false|for|function|goto|if|in|local|nil|not|or|repeat|return|then|true|until|while)\b"#)
    private static let number  = re(#"\b0[xX][0-9a-fA-F]+\b|\b\d+\.?\d*([eE][-+]?\d+)?\b"#)
    private static let dquote  = re(#""(\\.|[^"\\\n])*""#)
    private static let squote  = re(#"'(\\.|[^'\\\n])*'"#)
    private static let longStr = re(#"\[\[[\s\S]*?\]\]"#)
    private static let block   = re(#"--\[\[[\s\S]*?\]\]"#)
    private static let line    = re(#"--[^\n]*"#)

    private static func re(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [])
    }

    /// Re-color the whole storage. Cheap enough for a notebook code cell; callers
    /// invoke it on edit + on appearance change.
    public static func apply(to storage: NSTextStorage, dark: Bool, font: NSFont) {
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        guard full.length > 0 else { return }
        let p = SyntaxPalette.resolved(dark: dark)

        storage.beginEditing()
        storage.setAttributes([.foregroundColor: p.text, .font: font], range: full)
        color(number,  p.link,    in: text, full, storage)
        color(keyword, p.keyword, in: text, full, storage)
        color(longStr, p.string,  in: text, full, storage)
        color(dquote,  p.string,  in: text, full, storage)
        color(squote,  p.string,  in: text, full, storage)
        color(block,   p.comment, in: text, full, storage)
        color(line,    p.comment, in: text, full, storage)
        storage.endEditing()
    }

    private static func color(_ re: NSRegularExpression, _ c: NSColor,
                              in text: String, _ full: NSRange, _ storage: NSTextStorage) {
        re.enumerateMatches(in: text, range: full) { m, _, _ in
            if let r = m?.range, r.length > 0 { storage.addAttribute(.foregroundColor, value: c, range: r) }
        }
    }
}
