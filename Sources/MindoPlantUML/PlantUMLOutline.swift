import Foundation
import MindoBase

/// Document-outline rows for a `.puml` source: one entry per `@startX…@endX`
/// diagram block, titled by its `title …` line / diagram type (reusing the
/// page model from the multi-page preview). The target is the UTF-8 byte offset
/// of the block's first line, so the editor scrolls there on click — the same
/// target shape markdown headings use. Pure + line-based for unit testing.
///
/// Replaces the previous behavior where `.puml` was (wrongly) outlined as
/// Markdown headings, which produced nothing useful.
public enum PlantUMLOutline {
    public static func items(for source: String) -> [OutlineItem] {
        let pages = PlantUMLPages.split(source)
        let lineByteOffsets = byteOffsetsByLine(source)
        return pages.map { page in
            let offset = page.firstLine < lineByteOffsets.count ? lineByteOffsets[page.firstLine] : 0
            return OutlineItem(title: page.title, depth: 0, target: String(offset))
        }
    }

    /// UTF-8 byte offset of the start of each line (line index → offset),
    /// matching `Outline.fromMarkdown`'s target encoding.
    private static func byteOffsetsByLine(_ source: String) -> [Int] {
        var offsets: [Int] = []
        var running = 0
        for line in source.components(separatedBy: "\n") {
            offsets.append(running)
            running += line.utf8.count + 1   // + consumed '\n'
        }
        return offsets
    }
}
