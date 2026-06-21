import XCTest
@testable import MindoCore

final class FuzzyMatchTests: XCTestCase {

    // MARK: - Basic subsequence semantics

    func testEmptyQueryMatchesEverythingWithZeroScore() {
        let r = FuzzyMatch.match(query: "", candidate: "anything.md")
        XCTAssertEqual(r, FuzzyMatch.Result(score: 0, matchedIndices: []))
    }

    func testNonSubsequenceFails() {
        // 'z' never appears.
        XCTAssertNil(FuzzyMatch.match(query: "cfgz", candidate: "config.swift"))
    }

    func testOutOfOrderFails() {
        // letters present but not in order.
        XCTAssertNil(FuzzyMatch.match(query: "gfc", candidate: "config"))
    }

    func testQueryLongerThanCandidateFails() {
        XCTAssertNil(FuzzyMatch.match(query: "configuration", candidate: "config"))
    }

    func testCaseInsensitive() {
        // c@0, f@3, g@5 in "config.swift" — case folded both sides.
        let r = FuzzyMatch.match(query: "CFG", candidate: "config.swift")
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.matchedIndices, [0, 3, 5])
    }

    // MARK: - Matched indices (for bolding)

    func testMatchedIndicesAreGreedyLeftmost() {
        // "ace" in "abcde" -> a@0, c@2, e@4
        let r = FuzzyMatch.match(query: "ace", candidate: "abcde")
        XCTAssertEqual(r?.matchedIndices, [0, 2, 4])
    }

    func testRepeatedQueryCharsAdvancePastConsumed() {
        // "ll" must match two distinct l's.
        let r = FuzzyMatch.match(query: "ll", candidate: "hello")
        XCTAssertEqual(r?.matchedIndices, [2, 3])
    }

    // MARK: - Scoring heuristics

    func testPrefixBeatsMidwordMatch() {
        let prefix = FuzzyMatch.match(query: "con", candidate: "config.swift")!
        let mid = FuzzyMatch.match(query: "con", candidate: "myconfig.swift")!
        XCTAssertGreaterThan(prefix.score, mid.score)
    }

    func testConsecutiveBeatsScattered() {
        let consecutive = FuzzyMatch.match(query: "abc", candidate: "abcxyz")!
        let scattered = FuzzyMatch.match(query: "abc", candidate: "axbxc")!
        XCTAssertGreaterThan(consecutive.score, scattered.score)
    }

    func testSeparatorBoundaryBonus() {
        // 'm' after '/' (separator) should score higher than 'm' mid-word.
        let boundary = FuzzyMatch.match(query: "m", candidate: "src/main")!
        let midword = FuzzyMatch.match(query: "m", candidate: "format")!
        XCTAssertGreaterThan(boundary.score, midword.score)
    }

    func testCamelCaseBoundaryBonus() {
        // 'V' in "MindMapView" is a camel hump -> boundary bonus.
        let camel = FuzzyMatch.match(query: "mv", candidate: "MindMapView")!
        let plain = FuzzyMatch.match(query: "mv", candidate: "mauve")!
        XCTAssertGreaterThan(camel.score, plain.score)
    }

    // MARK: - Ranking

    func testRankOrdersBestFirst() {
        let files = ["myconfig.swift", "config.swift", "constants.swift", "readme.md"]
        let ranked = FuzzyMatch.rank(files, query: "con") { $0 }.map(\.item)
        // config.swift (prefix, consecutive) should rank first; readme has no match and drops.
        XCTAssertEqual(ranked.first, "config.swift")
        XCTAssertFalse(ranked.contains("readme.md"))
    }

    func testRankEmptyQueryKeepsOrder() {
        let files = ["b.md", "a.md", "c.md"]
        let ranked = FuzzyMatch.rank(files, query: "") { $0 }.map(\.item)
        XCTAssertEqual(ranked, files)
    }

    func testRankTiesPreserveInputOrder() {
        // Two identical candidates -> identical score -> stable by input order.
        let files = ["aaa/x.md", "bbb/x.md"]
        let ranked = FuzzyMatch.rank(files, query: "x") { String($0.suffix(4)) }.map(\.item)
        XCTAssertEqual(ranked, files)
    }

    func testRankDropsNonMatches() {
        let files = ["alpha", "beta", "gamma"]
        let ranked = FuzzyMatch.rank(files, query: "zzz") { $0 }
        XCTAssertTrue(ranked.isEmpty)
    }
}
