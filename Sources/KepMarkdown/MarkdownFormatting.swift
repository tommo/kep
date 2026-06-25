import Foundation

/// Pure transforms that surround / prefix the user's selection with markdown
/// syntax. Each operation takes the full text + an `NSRange` (UTF-16) and
/// returns the new text plus the new selection range. Toolbar buttons in the
/// editor view call into these so the heavy lifting is testable without an
/// NSTextView.
public enum MarkdownFormatting {

    /// Wrap selection with `marker` on both sides. Toggling: if the selection
    /// is already wrapped with `marker`, strip it instead.
    public static func wrap(_ text: String, range: NSRange, with marker: String) -> (String, NSRange) {
        let nsText = text as NSString
        guard NSMaxRange(range) <= nsText.length else { return (text, range) }
        let inner = nsText.substring(with: range)

        // Toggle off when already surrounded by `marker`.
        let prefixStart = range.location - marker.count
        let suffixEnd = NSMaxRange(range) + marker.count
        if prefixStart >= 0, suffixEnd <= nsText.length,
           nsText.substring(with: NSRange(location: prefixStart, length: marker.count)) == marker,
           nsText.substring(with: NSRange(location: NSMaxRange(range), length: marker.count)) == marker
        {
            let head = nsText.substring(to: prefixStart)
            let tail = nsText.substring(from: suffixEnd)
            let joined = head + inner + tail
            let newRange = NSRange(location: prefixStart, length: range.length)
            return (joined, newRange)
        }

        let head = nsText.substring(to: range.location)
        let tail = nsText.substring(from: NSMaxRange(range))
        let placeholder = inner.isEmpty ? "text" : inner
        let joined = head + marker + placeholder + marker + tail
        let newRange = NSRange(
            location: range.location + marker.count,
            length: (placeholder as NSString).length
        )
        return (joined, newRange)
    }

    public static func bold(_ text: String, range: NSRange) -> (String, NSRange) {
        wrap(text, range: range, with: "**")
    }

    public static func italic(_ text: String, range: NSRange) -> (String, NSRange) {
        wrap(text, range: range, with: "*")
    }

    public static func inlineCode(_ text: String, range: NSRange) -> (String, NSRange) {
        wrap(text, range: range, with: "`")
    }

    /// Wrap the selection in a fenced code block (```), each fence on its own
    /// line. Blank lines are inserted around the block only when the
    /// selection isn't already at a line boundary, so we don't pile up empty
    /// lines. The returned range selects the inner content (caret on the
    /// empty middle line for an empty selection).
    public static func codeBlock(_ text: String, range: NSRange) -> (String, NSRange) {
        let nsText = text as NSString
        let selected = nsText.substring(with: range)
        let beforeChar = range.location > 0
            ? nsText.substring(with: NSRange(location: range.location - 1, length: 1)) : ""
        let afterLoc = NSMaxRange(range)
        let afterChar = afterLoc < nsText.length
            ? nsText.substring(with: NSRange(location: afterLoc, length: 1)) : ""
        let leading = (range.location == 0 || beforeChar == "\n") ? "" : "\n"
        let trailing = (afterLoc == nsText.length || afterChar == "\n") ? "" : "\n"
        let block = leading + "```\n" + selected + "\n```" + trailing
        let newText = nsText.replacingCharacters(in: range, with: block)
        // Inner content begins after the leading newline (if any) + "```\n".
        let innerLoc = range.location + (leading as NSString).length + 4
        let newRange = NSRange(location: innerLoc, length: (selected as NSString).length)
        return (newText, newRange)
    }

    /// Prepend `#`s to the line under `range`. Toggling between H1…H6 cycles
    /// through depths.
    public static func heading(_ text: String, range: NSRange, level: Int) -> (String, NSRange) {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: range)
        var line = nsText.substring(with: lineRange)
        let trailingNewline = line.hasSuffix("\n") ? "\n" : ""
        if trailingNewline == "\n" { line = String(line.dropLast()) }

        // Strip existing leading hashes.
        var stripped = line
        while stripped.hasPrefix("#") { stripped.removeFirst() }
        if stripped.hasPrefix(" ") { stripped.removeFirst() }

        let prefix = String(repeating: "#", count: max(1, min(6, level))) + " "
        let newLine = prefix + stripped + trailingNewline
        let newText = nsText.replacingCharacters(in: lineRange, with: newLine)
        let newRange = NSRange(
            location: lineRange.location + (prefix as NSString).length,
            length: (stripped as NSString).length
        )
        return (newText, newRange)
    }

    /// Prepend `marker` to every line in the selection's line range. `marker`
    /// is something like `- `, `1. `, `> `.
    public static func prefixLines(_ text: String, range: NSRange, with marker: String) -> (String, NSRange) {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: range)
        let block = nsText.substring(with: lineRange)
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        let trailingEmpty = block.hasSuffix("\n")
        var rebuilt: [String] = []
        for line in lines {
            if line.isEmpty && rebuilt.count == lines.count - 1 && trailingEmpty {
                rebuilt.append("")
            } else {
                rebuilt.append(marker + String(line))
            }
        }
        let joined = rebuilt.joined(separator: "\n")
        let newText = nsText.replacingCharacters(in: lineRange, with: joined)
        let newRange = NSRange(location: lineRange.location, length: (joined as NSString).length)
        return (newText, newRange)
    }

    public static func bulletList(_ text: String, range: NSRange) -> (String, NSRange) {
        prefixLines(text, range: range, with: "- ")
    }

    public static func numberedList(_ text: String, range: NSRange) -> (String, NSRange) {
        // Sequential numbering for the selected block.
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: range)
        let block = nsText.substring(with: lineRange)
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        var counter = 1
        var rebuilt: [String] = []
        for (i, line) in lines.enumerated() {
            if i == lines.count - 1 && line.isEmpty {
                rebuilt.append(""); continue
            }
            rebuilt.append("\(counter). \(line)")
            counter += 1
        }
        let joined = rebuilt.joined(separator: "\n")
        let newText = nsText.replacingCharacters(in: lineRange, with: joined)
        let newRange = NSRange(location: lineRange.location, length: (joined as NSString).length)
        return (newText, newRange)
    }

    public static func blockquote(_ text: String, range: NSRange) -> (String, NSRange) {
        prefixLines(text, range: range, with: "> ")
    }

    /// Toggle task checkboxes across the selected line(s) — the Obsidian
    /// "toggle checkbox status" action. Per line: an existing `- [ ] ` / `- [x] `
    /// flips its tick; a plain `- ` bullet gains a `[ ] `; any other non-blank
    /// line becomes a `- [ ] ` task; blank lines are left alone.
    public static func toggleTask(_ text: String, range: NSRange) -> (String, NSRange) {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: range)
        let block = nsText.substring(with: lineRange)
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        let trailingEmpty = block.hasSuffix("\n")
        var rebuilt: [String] = []
        for (i, sub) in lines.enumerated() {
            if sub.isEmpty && i == lines.count - 1 && trailingEmpty {
                rebuilt.append("")
            } else {
                rebuilt.append(toggleTaskLine(String(sub)))
            }
        }
        let joined = rebuilt.joined(separator: "\n")
        let newText = nsText.replacingCharacters(in: lineRange, with: joined)
        let newRange = NSRange(location: lineRange.location, length: (joined as NSString).length)
        return (newText, newRange)
    }

    private static func toggleTaskLine(_ line: String) -> String {
        let indentCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = String(line.prefix(indentCount))
        let rest = String(line.dropFirst(indentCount))
        let chars = Array(rest)
        // Existing task: "<bullet> [<state>] rest" → flip the state.
        if chars.count >= 6, "-*+".contains(chars[0]), chars[1] == " ",
           chars[2] == "[", chars[4] == "]", chars[5] == " " {
            let newState: Character = (chars[3] == " ") ? "x" : " "
            return "\(indent)\(chars[0]) [\(newState)] \(String(chars[6...]))"
        }
        // Plain bullet → add an unchecked box.
        if chars.count >= 2, "-*+".contains(chars[0]), chars[1] == " " {
            return "\(indent)\(chars[0]) [ ] \(String(chars[2...]))"
        }
        // Blank (indent-only) line: leave it be.
        if rest.isEmpty { return line }
        // Plain text → promote to a task item.
        return "\(indent)- [ ] \(rest)"
    }

    public static func link(_ text: String, range: NSRange, url: String) -> (String, NSRange) {
        let nsText = text as NSString
        guard NSMaxRange(range) <= nsText.length else { return (text, range) }
        let inner = nsText.substring(with: range)
        let label = inner.isEmpty ? "link text" : inner
        let head = nsText.substring(to: range.location)
        let tail = nsText.substring(from: NSMaxRange(range))
        let joined = head + "[\(label)](\(url))" + tail
        // Place caret inside the label so users can immediately retype.
        let newRange = NSRange(
            location: range.location + 1,
            length: (label as NSString).length
        )
        return (joined, newRange)
    }

    public static func image(_ text: String, range: NSRange, url: String) -> (String, NSRange) {
        let nsText = text as NSString
        guard NSMaxRange(range) <= nsText.length else { return (text, range) }
        let inner = nsText.substring(with: range)
        let alt = inner.isEmpty ? "image" : inner
        let head = nsText.substring(to: range.location)
        let tail = nsText.substring(from: NSMaxRange(range))
        let joined = head + "![\(alt)](\(url))" + tail
        let newRange = NSRange(
            location: range.location + 2,
            length: (alt as NSString).length
        )
        return (joined, newRange)
    }

    /// Strikethrough — wraps the selection in `~~`. Toggles off when
    /// already wrapped.
    public static func strikethrough(_ text: String, range: NSRange) -> (String, NSRange) {
        wrap(text, range: range, with: "~~")
    }

    /// HTML comment block around the selection. Useful for stashing
    /// scratch notes inside a document without affecting the rendered
    /// output. Toggles off if the selection is already inside `<!-- … -->`.
    public static func comment(_ text: String, range: NSRange) -> (String, NSRange) {
        let nsText = text as NSString
        guard NSMaxRange(range) <= nsText.length else { return (text, range) }
        let inner = nsText.substring(with: range)
        let openMarker = "<!-- "
        let closeMarker = " -->"
        let prefixStart = range.location - openMarker.count
        let suffixEnd = NSMaxRange(range) + closeMarker.count
        if prefixStart >= 0, suffixEnd <= nsText.length,
           nsText.substring(with: NSRange(location: prefixStart, length: openMarker.count)) == openMarker,
           nsText.substring(with: NSRange(location: NSMaxRange(range), length: closeMarker.count)) == closeMarker {
            let head = nsText.substring(to: prefixStart)
            let tail = nsText.substring(from: suffixEnd)
            let joined = head + inner + tail
            return (joined, NSRange(location: prefixStart, length: range.length))
        }
        let placeholder = inner.isEmpty ? "comment" : inner
        let head = nsText.substring(to: range.location)
        let tail = nsText.substring(from: NSMaxRange(range))
        let joined = head + openMarker + placeholder + closeMarker + tail
        let newRange = NSRange(
            location: range.location + openMarker.count,
            length: (placeholder as NSString).length
        )
        return (joined, newRange)
    }

    /// Insert a horizontal-rule (`---`) on its own paragraph at the
    /// current cursor location. Mirrors mindolph's `btnSeparator` action,
    /// but pads with the surrounding blank lines markdown needs to
    /// actually render the rule (a `---` line directly below text is
    /// parsed as a setext H2 underline, not a separator).
    ///
    /// Drops any existing selection — separators don't pair with content
    /// so the natural behavior is to replace + reposition the caret on
    /// the line below the rule.
    public static func horizontalRule(_ text: String, range: NSRange) -> (String, NSRange) {
        let nsText = text as NSString
        guard NSMaxRange(range) <= nsText.length else { return (text, range) }
        let head = nsText.substring(to: range.location)
        let tail = nsText.substring(from: NSMaxRange(range))
        // Need a blank line BEFORE: head must end with "\n\n" (or be empty).
        let leading: String
        if head.isEmpty || head.hasSuffix("\n\n") { leading = "" }
        else if head.hasSuffix("\n") { leading = "\n" }
        else { leading = "\n\n" }
        // Need a blank line AFTER: tail must start with "\n" (rule's own
        // newline) plus another "\n" before any text.
        let trailing: String
        if tail.isEmpty || tail.hasPrefix("\n\n") { trailing = "\n" }
        else if tail.hasPrefix("\n") { trailing = "\n" }
        else { trailing = "\n\n" }
        let block = leading + "---" + trailing
        let joined = head + block + tail
        // Caret on the line right after the rule — the user's most likely
        // next move is to keep typing under the separator.
        let cursor = (head as NSString).length + (block as NSString).length
        return (joined, NSRange(location: cursor, length: 0))
    }

    /// Column alignment markers for the GFM table separator row. `.none`
    /// emits the classic `---` sentinel; the others wrap with colons.
    public enum TableAlignment: Sendable {
        case none, left, center, right

        var separatorCell: String {
            switch self {
            case .none:   return " --- "
            case .left:   return " :--- "
            case .center: return " :---: "
            case .right:  return " ---: "
            }
        }
    }

    /// Insert a markdown table skeleton with `rows` body rows and `cols`
    /// columns, replacing the selection. Mirrors what mindolph's TableDialog
    /// emits — pass `alignment` to pin every column's alignment marker.
    public static func table(_ text: String, range: NSRange, rows: Int, cols: Int, alignment: TableAlignment = .none) -> (String, NSRange) {
        let r = max(1, rows), c = max(1, cols)
        let header = "| " + (1...c).map { "Header \($0)" }.joined(separator: " | ") + " |"
        let separator = "|" + String(repeating: alignment.separatorCell + "|", count: c)
        var bodyLines: [String] = []
        for _ in 0..<r {
            bodyLines.append("|" + String(repeating: "     |", count: c))
        }
        let table = ([header, separator] + bodyLines).joined(separator: "\n")
        let nsText = text as NSString
        guard NSMaxRange(range) <= nsText.length else { return (text, range) }
        let head = nsText.substring(to: range.location)
        let tail = nsText.substring(from: NSMaxRange(range))
        let leading = head.isEmpty || head.hasSuffix("\n\n") ? "" : (head.hasSuffix("\n") ? "\n" : "\n\n")
        let trailing = tail.hasPrefix("\n") ? "" : "\n"
        let block = leading + table + trailing
        let joined = head + block + tail
        let cursorOffset = (head as NSString).length + (leading as NSString).length
        let newRange = NSRange(location: cursorOffset, length: (table as NSString).length)
        return (joined, newRange)
    }
}
