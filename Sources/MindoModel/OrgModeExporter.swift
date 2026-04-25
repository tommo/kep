import Foundation

/// Emits a mindmap as Org-Mode text. Mirrors the Java `ORGMODEExporter`
/// minus the numbered-list trick for deep levels (Mindo keeps depth as
/// stars all the way down — Org handles arbitrary depth fine in modern
/// readers). Output structure:
///
///     #+TITLE: <root text>
///     #+CREATOR: Mindo
///
///     * Root
///     ** Child
///     *** Grandchild
///     : note line one
///     : note line two
///     #+BEGIN_SRC swift
///     let x = 1
///     #+END_SRC
public enum OrgModeExporter {

    public static func export(_ map: MindMap) -> String {
        var out = ""
        let title = map.root?.text ?? ""
        out.append("#+TITLE: \(escapeHeading(title))\n")
        out.append("#+CREATOR: Mindo\n")
        out.append("\n")
        if let root = map.root {
            writeTopic(root, level: 0, into: &out)
        }
        return out
    }

    /// Recursive writer. `level` is the topic's depth (0 == root → one star).
    private static func writeTopic(_ topic: Topic, level: Int, into out: inout String) {
        let stars = String(repeating: "*", count: level + 1)
        out.append("\(stars) \(escapeHeading(topic.text))\n")

        // Note → `: prefix` block (Org's literal-text marker).
        if let note = topic.extra(.note) as? ExtraNote, !note.text.isEmpty {
            for line in note.text.split(separator: "\n", omittingEmptySubsequences: false) {
                out.append(": \(line)\n")
            }
        }

        // Link → URL line.
        if let link = topic.extra(.link) as? ExtraLink, !link.uri.isEmpty {
            out.append("URL: [[\(link.uri)]]\n")
        }

        // File → file:// link.
        if let file = topic.extra(.file) as? ExtraFile, !file.uri.isEmpty {
            out.append("FILE: [[\(file.uri)]]\n")
        }

        // Code snippets → BEGIN_SRC / END_SRC blocks, sorted by language for
        // stable output.
        let sortedLangs = topic.codeSnippets.keys.sorted()
        for lang in sortedLangs {
            guard let body = topic.codeSnippets[lang] else { continue }
            out.append("#+BEGIN_SRC \(lang)\n")
            out.append(body)
            if !body.hasSuffix("\n") { out.append("\n") }
            out.append("#+END_SRC\n")
        }

        for child in topic.children {
            writeTopic(child, level: level + 1, into: &out)
        }
    }

    /// Org headlines must stay on a single line — collapse newlines to spaces
    /// and drop ISO control characters that would corrupt the output.
    static func escapeHeading(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if ch == "\n" { out.append(" "); continue }
            if let scalar = ch.unicodeScalars.first, CharacterSet.controlCharacters.contains(scalar) { continue }
            out.append(ch)
        }
        return out
    }
}
