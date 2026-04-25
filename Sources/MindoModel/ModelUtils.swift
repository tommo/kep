import Foundation

/// Helpers that mirror `com.igormaznitsa.mindmap.model.ModelUtils` from the Java original.
public enum ModelUtils {

    /// Characters escaped with a leading backslash inside topic titles.
    static let escapedChars: Set<Character> = Set("\\`*_{}[]()#<>+-.!")

    public static func escapeMarkdown(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count * 2)
        for ch in text {
            if ch == "\n" {
                out.append("<br/>")
                continue
            }
            // Skip ISO control chars (Java's Character.isISOControl)
            if let scalar = ch.unicodeScalars.first, isISOControl(scalar) {
                continue
            }
            if escapedChars.contains(ch) {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }

    public static func unescapeMarkdown(_ text: String) -> String {
        // First convert `<br/>`, `<br>`, `< br />` etc back to newlines (case-insensitive).
        let s = text.replacingOccurrences(
            of: #"<\s*?br\s*?/?>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        // Then strip backslash escapes from `\<chr>` for chr in escapedChars.
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\\" {
                let next = s.index(after: i)
                if next < s.endIndex, escapedChars.contains(s[next]) {
                    out.append(s[next])
                    i = s.index(after: next)
                    continue
                }
            }
            out.append(ch)
            i = s.index(after: i)
        }
        return out
    }

    /// Wraps `text` in a `<pre>...</pre>` block, HTML-escaping it the same way the Java app does.
    public static func makePreBlock(_ text: String) -> String {
        return "<pre>\(escapeForPreBlock(text))</pre>"
    }

    /// HTML-escape `&`, `<`, `>` (the only entities the Java side emits inside <pre>).
    public static func escapeForPreBlock(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            default: out.append(ch)
            }
        }
        return out
    }

    /// Mirrors Apache Commons `StringEscapeUtils.unescapeHtml3` for the entities Mindolph emits.
    /// Handles named entities the Java app emits (`&amp; &lt; &gt; &quot; &apos; &nbsp;`)
    /// plus numeric (`&#nn;`) and hex (`&#xhh;`) entities.
    public static func unescapeHtml(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        out.reserveCapacity(text.count)
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch != "&" {
                out.append(ch)
                i = text.index(after: i)
                continue
            }
            // Find the matching `;` within a reasonable window (8 chars suffices for our entities).
            let scanEnd = text.index(i, offsetBy: 12, limitedBy: text.endIndex) ?? text.endIndex
            if let semi = text[i..<scanEnd].firstIndex(of: ";") {
                let entity = String(text[text.index(after: i)..<semi])
                if let replacement = Self.namedEntities[entity] {
                    out.append(replacement)
                    i = text.index(after: semi)
                    continue
                }
                if entity.hasPrefix("#") {
                    let body = entity.dropFirst()
                    if body.first == "x" || body.first == "X" {
                        if let code = UInt32(body.dropFirst(), radix: 16),
                           let scalar = Unicode.Scalar(code) {
                            out.append(Character(scalar))
                            i = text.index(after: semi)
                            continue
                        }
                    } else if let code = UInt32(body), let scalar = Unicode.Scalar(code) {
                        out.append(Character(scalar))
                        i = text.index(after: semi)
                        continue
                    }
                }
            }
            // Not a recognized entity — pass through literally.
            out.append(ch)
            i = text.index(after: i)
        }
        return out
    }

    /// Backtick-fence a value the way the Java side does for `key=` `value` in attribute lines.
    public static func makeMDCodeBlock(_ text: String) -> String {
        let count = max(1, calcMaxBacktickRun(in: text) + 1)
        let fence = String(repeating: "`", count: count)
        return fence + text + fence
    }

    /// Longest run of consecutive backticks anywhere in `text`.
    public static func calcMaxBacktickRun(in text: String) -> Int {
        var maxRun = 0
        var run = 0
        for ch in text {
            if ch == "`" { run += 1; if run > maxRun { maxRun = run } }
            else { run = 0 }
        }
        return maxRun
    }

    public static func calcLeadingHashes(_ text: String) -> Int {
        var n = 0
        for ch in text {
            if ch == "#" { n += 1 } else { break }
        }
        return n
    }

    public static func removeISOControls(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            if let scalar = ch.unicodeScalars.first, isISOControl(scalar) { continue }
            out.append(ch)
        }
        return out
    }

    private static func isISOControl(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return v <= 0x1F || (v >= 0x7F && v <= 0x9F)
    }

    private static let namedEntities: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "copy": "©", "reg": "®", "trade": "™",
    ]
}
