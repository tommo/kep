import Foundation

/// A small marker glyph shown on an outline row — the dependency-free mirror of
/// the canvas `PropertyMarker` (MindoBase can't import MindoModel). The producer
/// maps its typed markers to these; `OutlinePanel` resolves the tint to a color.
public struct OutlineMarker: Hashable {
    public enum Tint: Hashable {
        case priority(Int)   // 1...5 — colored like the canvas flag
        case done            // green check
        case todo            // hollow / dimmed
        case accent          // progress etc.
        case neutral         // tags
    }
    public let symbolName: String
    public let tint: Tint
    public init(symbolName: String, tint: Tint) {
        self.symbolName = symbolName
        self.tint = tint
    }
}

/// One row in the outline panel. Mirrors `OutlineItemData` from `mindolph-core`.
public struct OutlineItem: Identifiable, Hashable {
    public let id = UUID()
    public var title: String
    public var depth: Int
    /// Typed-property markers (priority/done/progress/tags) for this row, mirrored
    /// from the canvas. Empty for non-mindmap outlines (markdown/PlantUML).
    public var markers: [OutlineMarker] = []
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
    /// True when this node has children in the model (regardless of whether they
    /// are shown) — drives the disclosure chevron. False for leaves / non-mindmap.
    public var hasChildren: Bool = false
    /// True when this node is folded on the canvas, so its descendants are
    /// omitted from the outline (mirroring the canvas). Only meaningful with
    /// `hasChildren`.
    public var isCollapsed: Bool = false

    public init(title: String, depth: Int, target: String, breadcrumb: String = "",
                markers: [OutlineMarker] = [], hasChildren: Bool = false, isCollapsed: Bool = false) {
        self.title = title
        self.depth = depth
        self.target = target
        self.breadcrumb = breadcrumb
        self.markers = markers
        self.hasChildren = hasChildren
        self.isCollapsed = isCollapsed
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
