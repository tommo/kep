import Foundation
import MindoCore

/// Locates a Markdown heading by its (slugified) title and returns the UTF-8
/// byte offset of its line — the same offset scheme the editor's navigation
/// uses. Powers scrolling to `[[doc#heading]]` after opening the target doc.
/// Pure/testable.
public enum MarkdownHeadingIndex {
    /// Byte offset of the first heading whose slug matches `heading`'s slug, or
    /// nil if none. Matching is by GitHub-style slug so case/spacing/punctuation
    /// differences don't matter.
    public static func byteOffset(forHeading heading: String, in markdown: String) -> Int? {
        let targetSlug = MarkdownRenderer.slugify(heading)
        guard !targetSlug.isEmpty else { return nil }
        var byte = 0
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if let title = headingTitle(in: raw), MarkdownRenderer.slugify(title) == targetSlug {
                return byte
            }
            byte += raw.utf8.count + 1   // +1 for the '\n' the split consumed
        }
        return nil
    }

    /// The title of an ATX heading line (`## Title`), else nil.
    static func headingTitle(in line: String) -> String? {
        var i = line.startIndex
        var depth = 0
        while i < line.endIndex, line[i] == "#", depth < 6 {
            i = line.index(after: i); depth += 1
        }
        guard depth >= 1, i < line.endIndex, line[i] == " " else { return nil }
        return String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)
    }
}
