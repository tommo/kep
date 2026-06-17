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
}
