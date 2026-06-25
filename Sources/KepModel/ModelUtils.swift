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
            if ch.isISOControl { continue }
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

    /// XML/HTML-escape `&`, `<`, `>` (always); also `"`/`'` when `quotes` is
    /// true (for attribute values). The one escaper shared by the `<pre>` note
    /// body (quotes:false) and the FreeMind exporter (quotes:true).
    public static func escapeXML(_ text: String, quotes: Bool) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            case "\"" where quotes: out.append("&quot;")
            case "'" where quotes: out.append("&apos;")
            default: out.append(ch)
            }
        }
        return out
    }

    /// HTML-escape `&`, `<`, `>` (the only entities the Java side emits inside <pre>).
    public static func escapeForPreBlock(_ text: String) -> String {
        escapeXML(text, quotes: false)
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

    /// Backtick-fence an attribute value (the `key=` `value` form on `> ` lines).
    ///
    /// Round-trips ANY string (#211). Steps:
    /// 1. Escape `\`, newline and CR so the value stays on the single `> ` line
    ///    (a raw newline would split the line and lose everything after it).
    /// 2. Fence with `maxBacktickRun + 1` backticks (so internal runs can't close
    ///    the span early).
    /// 3. If the escaped value abuts the fence with a backtick, pad one space on
    ///    each side — otherwise a value-edge backtick merges with the closing
    ///    fence and the parser drops it. The reader strips that padding back off
    ///    (CommonMark code-span rule). Normal values (no `\`, newline, or edge
    ///    backtick) are emitted byte-for-byte as before.
    public static func makeMDCodeBlock(_ text: String) -> String {
        let escaped = escapeAttributeValue(text)
        let count = max(1, calcMaxBacktickRun(in: escaped) + 1)
        let fence = String(repeating: "`", count: count)
        let needsPad = escaped.first == "`" || escaped.last == "`"
        let body = needsPad ? " " + escaped + " " : escaped
        return fence + body + fence
    }

    /// Escape the characters that can't survive inside a single-line `> ` value:
    /// backslash (the escape introducer) and the line breaks. Inverse of
    /// `unescapeAttributeValue`.
    public static func escapeAttributeValue(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            default:   out.append(ch)
            }
        }
        return out
    }

    /// Reverse `escapeAttributeValue`. An unknown `\x` escape is passed through
    /// literally (keeps the backslash) so values from older files that contain a
    /// raw backslash followed by an ordinary character are preserved.
    public static func unescapeAttributeValue(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\\", s.index(after: i) < s.endIndex {
                let next = s.index(after: i)
                switch s[next] {
                case "\\": out.append("\\"); i = s.index(after: next); continue
                case "n":  out.append("\n"); i = s.index(after: next); continue
                case "r":  out.append("\r"); i = s.index(after: next); continue
                default:   break   // unknown escape — keep the backslash literally
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }

    /// CommonMark code-span rule: if a fenced value both begins and ends with a
    /// space but isn't all spaces, one space is removed from each end. Undoes the
    /// edge-backtick padding `makeMDCodeBlock` adds.
    public static func stripCodeSpanPadding(_ s: String) -> String {
        guard s.count >= 2, s.first == " ", s.last == " ",
              s.contains(where: { $0 != " " }) else { return s }
        return String(s.dropFirst().dropLast())
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
            if ch.isISOControl { continue }
            out.append(ch)
        }
        return out
    }

    private static let namedEntities: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "copy": "©", "reg": "®", "trade": "™",
    ]
}
