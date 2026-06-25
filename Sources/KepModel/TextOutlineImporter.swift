import Foundation

/// Reads an indented text outline (one topic per line, indent = nesting)
/// and builds a MindMap. Mirrors Mindolph's `Text2MindMapImporter`.
///
/// Indentation rules — match what most "outline" tools accept:
///   - Tabs OR spaces are valid; the indent unit is auto-detected from the
///     first non-zero-indent line (its leading whitespace becomes one
///     level). Mixed tabs+spaces fall back to "any leading whitespace = 1
///     level deeper".
///   - Bullet markers `-`, `*`, `•`, `+` are stripped (with one optional
///     space) so both `- A` and `A` are accepted.
///   - Blank lines are skipped.
///
/// First non-blank line becomes the root.
public enum TextOutlineImporter {

    public enum ImportError: Error {
        case empty
    }

    public static func parse(_ text: String) throws -> MindMap {
        let lines = text
            .components(separatedBy: "\n")
            .map { stripTrailingCR($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw ImportError.empty }

        // Detect indent unit from the first indented line.
        let indentUnit = detectIndentUnit(lines)

        let map = MindMap()
        var stack: [(level: Int, topic: Topic)] = []

        for raw in lines {
            let level = depth(of: raw, indentUnit: indentUnit)
            let text = stripBullet(raw.dropFirst(raw.prefix(while: { $0 == " " || $0 == "\t" }).count))
            // Pop stack until the parent has level == level - 1.
            while let last = stack.last, last.level >= level {
                stack.removeLast()
            }
            if let parent = stack.last?.topic {
                let child = parent.addChild(text: text)
                stack.append((level: level, topic: child))
            } else {
                // First node → root. Subsequent zero-indent nodes also
                // attach as root children to keep the tree single-rooted.
                if let root = map.root {
                    let child = root.addChild(text: text)
                    stack.append((level: level + 1, topic: child))
                } else {
                    let root = Topic(text: text)
                    map.root = root
                    stack.append((level: 0, topic: root))
                }
            }
        }
        return map
    }

    /// Number of indent units at the start of a line. Mixed-indent lines
    /// degrade gracefully — every non-zero leading whitespace block counts
    /// as at least 1 level deeper than zero-indent.
    static func depth(of line: String, indentUnit: String) -> Int {
        let leading = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        if leading.isEmpty { return 0 }
        if !indentUnit.isEmpty {
            // Try clean division first.
            if leading.count % indentUnit.count == 0 {
                let attempt = leading.count / indentUnit.count
                if String(repeating: indentUnit, count: attempt) == leading { return attempt }
            }
        }
        // Fallback: count tabs as 1, every two spaces as 1, otherwise +1.
        return max(1, leading.filter { $0 == "\t" }.count + leading.filter { $0 == " " }.count / 2)
    }

    /// Inspect non-zero-indent lines to guess the indent unit. Returns
    /// "\t" when any line is tab-indented; otherwise the shortest
    /// space-only leading run.
    static func detectIndentUnit(_ lines: [String]) -> String {
        for line in lines {
            let leading = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            if leading.contains("\t") { return "\t" }
        }
        var minRun = Int.max
        for line in lines {
            let leading = String(line.prefix(while: { $0 == " " }))
            if !leading.isEmpty { minRun = min(minRun, leading.count) }
        }
        return minRun == Int.max ? "  " : String(repeating: " ", count: minRun)
    }

    /// Drop a leading bullet marker (`-`, `*`, `•`, `+`) and one optional
    /// space. Trims trailing whitespace.
    static func stripBullet<S: StringProtocol>(_ line: S) -> String {
        var s = String(line)
        if let first = s.first, "-*•+".contains(first) {
            s.removeFirst()
            if s.first == " " { s.removeFirst() }
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    }

    private static func stripTrailingCR(_ s: String) -> String {
        s.hasSuffix("\r") ? String(s.dropLast()) : s
    }
}
