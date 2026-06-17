import Foundation

/// One reference TO a document — the source file plus the specific wiki link
/// that points at the target. Powers a "Linked mentions / Backlinks" panel,
/// the other half of the knowledge base.
public struct Backlink: Equatable, Sendable {
    public let source: URL       // the file that contains the reference
    public let link: WikiLink

    public init(source: URL, link: WikiLink) {
        self.source = source
        self.link = link
    }
}

/// A source document that references the target, with the context line around
/// each `[[link]]` — the row model for a "Linked mentions" panel.
public struct LinkedMention: Equatable, Sendable {
    public let source: URL
    public let snippets: [String]   // trimmed line of text containing each reference

    public init(source: URL, snippets: [String]) {
        self.source = source
        self.snippets = snippets
    }
}

public enum Backlinks {
    /// Find every reference that resolves to `target`. `corpus` is the set of
    /// (file URL, its text) to scan; `allFiles` is the resolution namespace
    /// (typically every workspace file) so `[[Notes]]` resolves the same way it
    /// would when clicked. The target file never lists itself.
    ///
    /// Pure so the scan is unit-testable without touching disk; the app builds
    /// the corpus by reading workspace files.
    public static func to(_ target: URL,
                          corpus: [(url: URL, text: String)],
                          allFiles: [URL]) -> [Backlink] {
        let targetStd = target.standardizedFileURL
        var out: [Backlink] = []
        for entry in corpus {
            if entry.url.standardizedFileURL == targetStd { continue }   // skip self
            for link in WikiLinkParser.links(in: entry.text) {
                guard !link.target.isEmpty,                              // in-doc heading, not a cross-ref
                      let resolved = WikiLinkResolver.resolve(link.target, in: allFiles),
                      resolved.standardizedFileURL == targetStd else { continue }
                out.append(Backlink(source: entry.url, link: link))
            }
        }
        return out
    }

    /// Distinct source files that reference `target`, in stable path order —
    /// the headline count for a backlinks panel.
    public static func sources(to target: URL,
                               corpus: [(url: URL, text: String)],
                               allFiles: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []
        for b in to(target, corpus: corpus, allFiles: allFiles) {
            let key = b.source.standardizedFileURL.path
            if seen.insert(key).inserted { ordered.append(b.source) }
        }
        return ordered.sorted { $0.path < $1.path }
    }

    /// Group every reference to `target` by source document, with the trimmed
    /// context line around each `[[link]]`. Sources are in stable path order;
    /// within a source, snippets follow document order. Powers the "Linked
    /// mentions" panel. Pure → unit-testable.
    public static func mentions(to target: URL,
                                corpus: [(url: URL, text: String)],
                                allFiles: [URL]) -> [LinkedMention] {
        var textByURL: [String: String] = [:]
        for entry in corpus { textByURL[entry.url.standardizedFileURL.path] = entry.text }

        var order: [URL] = []
        var snippetsBySource: [String: [String]] = [:]
        for b in to(target, corpus: corpus, allFiles: allFiles) {
            let key = b.source.standardizedFileURL.path
            if snippetsBySource[key] == nil { snippetsBySource[key] = []; order.append(b.source) }
            if let text = textByURL[key] {
                snippetsBySource[key]?.append(contextLine(in: text, around: b.link.nsRange))
            }
        }
        return order
            .sorted { $0.path < $1.path }
            .map { LinkedMention(source: $0, snippets: snippetsBySource[$0.standardizedFileURL.path] ?? []) }
    }

    /// The single line of `text` containing `range`, trimmed of surrounding
    /// whitespace. Clamps out-of-bounds ranges so it never traps.
    static func contextLine(in text: String, around range: NSRange) -> String {
        let ns = text as NSString
        guard ns.length > 0 else { return "" }
        let loc = max(0, min(range.location, ns.length - 1))
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        return ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
