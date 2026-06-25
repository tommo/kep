import Foundation

/// Splits a `.puml` source into its individual diagram "pages" — each
/// `@startX … @endX` block. javamind parity: a file may hold several diagrams
/// and the preview renders one page at a time, switching as the caret moves
/// between blocks. Pure + line-based so it's unit-testable.
public enum PlantUMLPages {

    public struct Page: Equatable, Sendable {
        public let index: Int
        /// Display title — an in-block `title …`, else the diagram type, else "Page N".
        public let title: String
        /// 0-based inclusive line span of the block in the source.
        public let firstLine: Int
        public let lastLine: Int
        /// The exact block text (the `@start…@end` slice) handed to the renderer.
        public let text: String

        public func contains(line: Int) -> Bool { line >= firstLine && line <= lastLine }
    }

    /// All diagram pages in `source`, in document order. When no `@start` fence
    /// is present the whole source is returned as a single page (so callers can
    /// always render `pages[active]`).
    public static func split(_ source: String) -> [Page] {
        let lines = source.components(separatedBy: "\n")
        var pages: [Page] = []
        var blockStart: Int? = nil
        var typeName: String = ""

        for (i, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("@start") {
                blockStart = i
                typeName = String(lower.dropFirst("@start".count))   // "uml", "gantt", …
            } else if lower.hasPrefix("@end"), let start = blockStart {
                let slice = Array(lines[start...i])
                pages.append(Page(
                    index: pages.count,
                    title: pageTitle(in: slice, type: typeName, ordinal: pages.count + 1),
                    firstLine: start,
                    lastLine: i,
                    text: slice.joined(separator: "\n")
                ))
                blockStart = nil
            }
        }

        if pages.isEmpty {
            return [Page(index: 0, title: "Diagram", firstLine: 0,
                         lastLine: max(lines.count - 1, 0), text: source)]
        }
        return pages
    }

    /// The page whose block contains `line`; if the line sits between/outside
    /// blocks, the nearest preceding page (so caret moves in the gap keep the
    /// last diagram shown). nil only when there are no pages.
    public static func pageIndex(forLine line: Int, in pages: [Page]) -> Int? {
        guard !pages.isEmpty else { return nil }
        if let exact = pages.first(where: { $0.contains(line: line) }) { return exact.index }
        // Nearest preceding block, else the first.
        let preceding = pages.last { $0.firstLine <= line }
        return (preceding ?? pages[0]).index
    }

    private static func pageTitle(in lines: [String], type: String, ordinal: Int) -> String {
        for raw in lines {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("title ") {
                let title = t.dropFirst("title ".count).trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !title.isEmpty { return title }
            }
        }
        if !type.isEmpty { return type.capitalized + " " + String(ordinal) }
        return "Page \(ordinal)"
    }
}
