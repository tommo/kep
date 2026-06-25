import Foundation

/// Emits a mindmap as Markdown text. Mirrors mindolph's
/// `MarkdownExporter` (which delegates to `ConvertUtils.convertTopics`):
/// the top 5 levels become `#`..`#####` headings; deeper levels become
/// indented `* ` bullets so very-deep trees still render reasonably in
/// any markdown viewer.
///
/// Extras (note / link / file) are emitted under each topic as
/// blockquotes / fenced blocks, matching the Java output structure
/// closely enough that round-tripping through a markdown viewer keeps
/// the same visual hierarchy.
public enum MindMapMarkdownExporter {

    /// Levels 0-4 (root + first 4 children deep) get a `#` heading;
    /// anything past that becomes a bullet to avoid `######` heading
    /// soup that most renderers stop styling.
    public static let headingLevelCutoff: Int = 5

    public static func export(_ map: MindMap) -> String {
        var out = ""
        if let root = map.root {
            writeTopic(root, level: 0, into: &out)
        }
        return out
    }

    private static func writeTopic(_ topic: Topic, level: Int, into out: inout String) {
        let title = escapeMarkdown(topic.text)
        if level < headingLevelCutoff {
            let prefix = String(repeating: "#", count: level + 1)
            out.append("\(prefix) \(title)\n")
        } else {
            let indent = String(repeating: "  ", count: level - headingLevelCutoff)
            out.append("\(indent)* \(title)\n")
        }

        // Note → blockquote so it visually attaches to the heading above.
        if let note = topic.extra(.note) as? ExtraNote, !note.text.isEmpty {
            for line in note.text.split(separator: "\n", omittingEmptySubsequences: false) {
                out.append("> \(line)\n")
            }
        }
        // Link → italic line under the heading. Uses the bare URI as the
        // visible text — keeps it greppable and matches mindolph's
        // `> Url:` convention without the awkward leading-quote.
        if let link = topic.extra(.link) as? ExtraLink, !link.uri.isEmpty {
            out.append("[\(link.uri)](\(link.uri))\n")
        }
        if let file = topic.extra(.file) as? ExtraFile, !file.uri.isEmpty {
            out.append("[\(file.uri)](\(file.uri))\n")
        }

        // Code snippets → fenced blocks, language tagged. Sorted for
        // stable output (same convention as OrgModeExporter).
        let sortedLangs = topic.codeSnippets.keys.sorted()
        for lang in sortedLangs {
            guard let body = topic.codeSnippets[lang] else { continue }
            // Widen the fence past any backtick run inside the body so a snippet
            // that itself contains ``` doesn't terminate the block early.
            let fence = String(repeating: "`", count: max(3, ModelUtils.calcMaxBacktickRun(in: body) + 1))
            out.append("\(fence)\(lang)\n")
            out.append(body)
            if !body.hasSuffix("\n") { out.append("\n") }
            out.append("\(fence)\n")
        }

        for child in topic.children {
            writeTopic(child, level: level + 1, into: &out)
        }
    }

    /// Escape the small set of markdown characters that would break a
    /// heading or bullet line if they appeared in topic text. We don't
    /// touch characters that markdown allows mid-line (`_`, `*` inside
    /// a heading render fine in most renderers).
    static func escapeMarkdown(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            // Collapse newlines to space — markdown headings end at \n.
            if ch == "\n" || ch == "\r" { out.append(" "); continue }
            // Drop control characters.
            if let scalar = ch.unicodeScalars.first, CharacterSet.controlCharacters.contains(scalar) { continue }
            out.append(ch)
        }
        return out
    }
}
