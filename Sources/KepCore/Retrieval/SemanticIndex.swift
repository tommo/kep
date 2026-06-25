import Foundation

/// Produces a fixed-length embedding vector for a piece of text. Abstracted so
/// the retrieval index is unit-testable with a deterministic fake; the live
/// implementation (`NLTextEmbedder`) uses Apple's on-device NaturalLanguage
/// sentence embeddings.
public protocol TextEmbedder {
    func vector(for text: String) -> [Double]?
}

public enum VectorMath {
    /// Cosine similarity in [-1, 1]; 0 for empty/zero/length-mismatched vectors.
    public static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = na.squareRoot() * nb.squareRoot()
        return denom == 0 ? 0 : dot / denom
    }
}

/// One retrieved passage with its relevance score.
public struct RetrievedChunk: Equatable, Sendable {
    public let doc: String
    public let text: String
    public let score: Double
    public init(doc: String, text: String, score: Double) {
        self.doc = doc; self.text = text; self.score = score
    }
}

/// A semantic search index: chunks every document, embeds each chunk once, and
/// answers nearest-neighbour queries by cosine similarity. Pure given an
/// injected `TextEmbedder` (so tests use a deterministic fake; the app uses
/// `NLTextEmbedder`).
public struct SemanticIndex {
    struct Entry { let doc: String; let text: String; let vector: [Double] }
    let entries: [Entry]

    public init(documents: [(doc: String, text: String)],
                embedder: TextEmbedder,
                maxChars: Int = 800,
                overlap: Int = 120) {
        var built: [Entry] = []
        for d in documents {
            for chunk in Chunker.chunks(of: d.text, maxChars: maxChars, overlap: overlap) {
                if let v = embedder.vector(for: chunk) {
                    built.append(Entry(doc: d.doc, text: chunk, vector: v))
                }
            }
        }
        entries = built
    }

    public var chunkCount: Int { entries.count }

    /// Top-`topK` chunks most similar to `query`, score-descending, positive
    /// scores only. Empty when the query can't be embedded or nothing matches.
    public func query(_ query: String, embedder: TextEmbedder, topK: Int = 5) -> [RetrievedChunk] {
        guard let qv = embedder.vector(for: query) else { return [] }
        return entries
            .map { RetrievedChunk(doc: $0.doc, text: $0.text, score: VectorMath.cosine(qv, $0.vector)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(max(0, topK))
            .map { $0 }
    }
}
