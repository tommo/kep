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
