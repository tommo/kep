import Foundation

/// Builds a knowledge-base context summary for a document — the documents it
/// links out to (resolved) and the documents that link back to it. Fed to the
/// AI assistant so it can reason across the vault, not just the open file.
/// Pure for unit-testing (the app supplies the corpus by reading workspace files).
public enum KBContext {

    /// A one-paragraph summary of `doc`'s links, or nil when it has none.
    /// `text` is `doc`'s content; `corpus` is (url, text) for backlink scanning;
    /// `allFiles` is the resolution namespace.
    public static func summary(for doc: URL,
                               text: String,
                               corpus: [(url: URL, text: String)],
                               allFiles: [URL]) -> String? {
        let outgoing = outgoingLinks(in: text, allFiles: allFiles)
        let incoming = Backlinks.sources(to: doc, corpus: corpus, allFiles: allFiles)
            .map { $0.deletingPathExtension().lastPathComponent }

        var parts: [String] = []
        if !outgoing.isEmpty {
            parts.append("Links to: " + outgoing.joined(separator: ", ") + ".")
        }
        if !incoming.isEmpty {
            parts.append("Linked from: " + incoming.joined(separator: ", ") + ".")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Distinct base names of the documents `text`'s `[[wiki links]]` resolve to,
    /// in first-seen order (unresolved links dropped).
    public static func outgoingLinks(in text: String, allFiles: [URL]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for link in WikiLinkParser.links(in: text) where !link.target.isEmpty {
            guard let url = WikiLinkResolver.resolve(link.target, in: allFiles) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            if seen.insert(name).inserted { out.append(name) }
        }
        return out
    }
}
