import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage

/// Live `TextEmbedder` backed by Apple's on-device NaturalLanguage sentence
/// embeddings (no network, no API key). `isAvailable` is false when the OS has
/// no embedding model for the language, in which case callers fall back to
/// literal search.
public final class NLTextEmbedder: TextEmbedder {
    private let embedding: NLEmbedding?

    public init(language: NLLanguage = .english) {
        self.embedding = NLEmbedding.sentenceEmbedding(for: language)
    }

    public var isAvailable: Bool { embedding != nil }

    public func vector(for text: String) -> [Double]? {
        guard let embedding else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Whole-chunk vector when the model accepts it; otherwise average the
        // per-sentence vectors so long chunks still embed.
        if let v = embedding.vector(for: trimmed) { return v }
        var sum: [Double] = []
        var n = 0
        let ns = trimmed as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: .bySentences) { sentence, _, _, _ in
            guard let s = sentence, let v = embedding.vector(for: s) else { return }
            if sum.isEmpty { sum = v } else { for i in v.indices { sum[i] += v[i] } }
            n += 1
        }
        guard n > 0 else { return nil }
        return sum.map { $0 / Double(n) }
    }
}
#endif
