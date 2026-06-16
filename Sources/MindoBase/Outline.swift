import Foundation

/// One row in the outline panel. Mirrors `OutlineItemData` from `mindolph-core`.
public struct OutlineItem: Identifiable, Hashable {
    public let id = UUID()
    public var title: String
    public var depth: Int
    /// Symbolic location used by the editor to navigate when this item is
    /// clicked. The exact shape is per-editor — character offsets for text
    /// editors, topic UIDs for mind maps, etc. Encoded as a string so the
    /// model is purely data.
    public var target: String
    /// Ancestor-path breadcrumb (e.g. "Root › Branch › Leaf"), used by the
    /// Go to Node palette to disambiguate same-named nodes and to fuzzy-match
    /// across the hierarchy. Empty when there's no meaningful path (markdown
    /// headings, or the root itself).
    public var breadcrumb: String

    public init(title: String, depth: Int, target: String, breadcrumb: String = "") {
        self.title = title
        self.depth = depth
        self.target = target
        self.breadcrumb = breadcrumb
    }
}

/// Pure-function outline extractor. Each editor module supplies its own.
public enum Outline {
    /// Extract headings from Markdown text. Lines that match `^#{1,6}[ ]+...`
    /// become items; depth = number of leading hashes. Target is the byte
    /// offset of the heading line so the editor can scroll to it.
    public static func fromMarkdown(_ text: String) -> [OutlineItem] {
        var items: [OutlineItem] = []
        var offset = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineLength = line.utf8.count + 1  // include the consumed '\n'
            if let match = matchHeading(line) {
                items.append(OutlineItem(title: match.title, depth: match.depth, target: String(offset)))
            }
            offset += lineLength
        }
        return items
    }

    private static func matchHeading(_ line: Substring) -> (depth: Int, title: String)? {
        var depth = 0
        var idx = line.startIndex
        while idx < line.endIndex && line[idx] == "#" && depth < 6 {
            depth += 1
            idx = line.index(after: idx)
        }
        guard depth >= 1, idx < line.endIndex, line[idx] == " " else { return nil }
        let title = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (depth, title)
    }
}
