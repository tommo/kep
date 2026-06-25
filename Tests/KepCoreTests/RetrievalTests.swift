import XCTest
@testable import KepCore

final class RetrievalTests: XCTestCase {

    /// Deterministic bag-of-words embedder: hashes each word to a fixed dim and
    /// counts. Cosine then reflects word overlap — enough to test ranking
    /// without the OS embedding model.
    struct BagOfWordsEmbedder: TextEmbedder {
        let dims = 64
        func vector(for text: String) -> [Double]? {
            let words = text.lowercased().split { !$0.isLetter }
            guard !words.isEmpty else { return nil }
            var v = [Double](repeating: 0, count: dims)
            for w in words {
                let h = w.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) }
                v[((h % dims) + dims) % dims] += 1
            }
            return v
        }
    }

    // MARK: - Chunker

    func testShortTextIsOneChunk() {
        let c = Chunker.chunks(of: "Just a short note.", maxChars: 800)
        XCTAssertEqual(c, ["Just a short note."])
    }

    func testParagraphsPackedWithinLimit() {
        let para = String(repeating: "word ", count: 50)   // ~250 chars
        let text = (1...6).map { "\($0) \(para)" }.joined(separator: "\n\n")
        let chunks = Chunker.chunks(of: text, maxChars: 300, overlap: 40)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks { XCTAssertLessThanOrEqual(chunk.count, 300) }
    }

    func testOversizedParagraphHardSplit() {
        let big = String(repeating: "a", count: 1000)
        let chunks = Chunker.chunks(of: big, maxChars: 300, overlap: 0)
        XCTAssertEqual(chunks.count, 4)        // 300+300+300+100
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 300 })
    }

    func testEmptyText() {
        XCTAssertTrue(Chunker.chunks(of: "\n\n   \n").isEmpty)
    }

    // MARK: - VectorMath

    func testCosineIdenticalIsOne() {
        XCTAssertEqual(VectorMath.cosine([1, 2, 3], [1, 2, 3]), 1.0, accuracy: 1e-9)
    }

    func testCosineOrthogonalIsZero() {
        XCTAssertEqual(VectorMath.cosine([1, 0], [0, 1]), 0.0, accuracy: 1e-9)
    }

    func testCosineGuardsEmptyAndMismatch() {
        XCTAssertEqual(VectorMath.cosine([], []), 0)
        XCTAssertEqual(VectorMath.cosine([1, 2], [1]), 0)
        XCTAssertEqual(VectorMath.cosine([0, 0], [0, 0]), 0)
    }

    // MARK: - SemanticIndex

    func testQueryRanksMostRelevantDocFirst() {
        let docs = [
            (doc: "Coffee", text: "Espresso extraction depends on grind size and pressure."),
            (doc: "Travel", text: "Booking flights early saves money on long trips abroad."),
            (doc: "Gardening", text: "Tomatoes need full sun and regular watering to fruit."),
        ]
        let index = SemanticIndex(documents: docs, embedder: BagOfWordsEmbedder())
        XCTAssertEqual(index.chunkCount, 3)
        let hits = index.query("how does espresso grind pressure affect extraction",
                               embedder: BagOfWordsEmbedder(), topK: 2)
        XCTAssertFalse(hits.isEmpty)
        XCTAssertEqual(hits.first?.doc, "Coffee")
        XCTAssertLessThanOrEqual(hits.count, 2)
        // scores are sorted descending
        XCTAssertEqual(hits.map(\.score), hits.map(\.score).sorted(by: >))
    }

    func testQueryWithNoOverlapReturnsNothing() {
        let docs = [(doc: "A", text: "alpha beta gamma")]
        let hits = SemanticIndex(documents: docs, embedder: BagOfWordsEmbedder())
            .query("zzz", embedder: BagOfWordsEmbedder())
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - Live embedder (skipped when the OS model is absent)

    func testNLEmbedderProducesVectors() throws {
        let embedder = NLTextEmbedder()
        try XCTSkipUnless(embedder.isAvailable, "No NL sentence-embedding model on this host")
        let v = embedder.vector(for: "The quick brown fox jumps over the lazy dog.")
        XCTAssertNotNil(v)
        XCTAssertGreaterThan(v?.count ?? 0, 0)
    }
}
