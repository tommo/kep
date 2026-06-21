import Foundation

/// A lightweight, line-level classification of prose-cell markdown for display
/// rendering (headings / bullets / inline text), avoiding a per-cell WKWebView.
/// Inline emphasis within each line is rendered by SwiftUI via
/// `AttributedString(markdown:)`; this just identifies block shape per line.
public enum ProseLine: Equatable, Sendable {
    case heading(level: Int, text: String)
    case bullet(text: String)
    case text(String)
    case blank
}

public enum ProseMarkdown {
    /// Classify each line of `markdown` for rendering. Pure + testable.
    public static func lines(_ markdown: String) -> [ProseLine] {
        markdown.components(separatedBy: "\n").map(classify)
    }

    static func classify(_ raw: String) -> ProseLine {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return .blank }
        // ATX heading: 1–6 '#' then a space.
        if line.first == "#" {
            let hashes = line.prefix(while: { $0 == "#" })
            let level = hashes.count
            if level >= 1, level <= 6 {
                let rest = line.dropFirst(level)
                if rest.first == " " {
                    return .heading(level: level, text: rest.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        // Bullet: -, *, or + followed by a space.
        if let f = line.first, "-*+".contains(f), line.dropFirst().first == " " {
            return .bullet(text: line.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
        return .text(line)
    }
}
