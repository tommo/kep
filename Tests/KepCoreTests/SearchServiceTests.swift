import XCTest
@testable import KepCore

final class SearchServiceTests: XCTestCase {

    func testScanFindsMultipleMatchesPerLineAndAcrossLines() {
        let svc = SearchService()
        let text = """
        alpha beta alpha
        gamma
        ALPHA delta
        """
        let hits = svc.scan(text: text, query: "alpha")
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(hits[0].lineNumber, 1)
        XCTAssertEqual(hits[1].lineNumber, 1)
        XCTAssertEqual(hits[2].lineNumber, 3)
    }

    func testCaseSensitivityRespectsOption() {
        let svc = SearchService()
        let text = "Hello world\nhello again"
        XCTAssertEqual(svc.scan(text: text, query: "Hello").count, 2)
        XCTAssertEqual(svc.scan(text: text, query: "Hello", options: SearchOptions(caseSensitive: true)).count, 1)
    }

    func testEmptyQueryReturnsNothing() {
        let svc = SearchService()
        XCTAssertTrue(svc.scan(text: "anything", query: "").isEmpty)
    }

    func testWholeWordOnlyMatchesAtBoundaries() {
        let svc = SearchService()
        let text = "map mapping mind-map remap\ntop maps"
        // Without whole-word: every "map" substring matches.
        XCTAssertEqual(svc.scan(text: text, query: "map").count, 5)
        // With whole-word: only the standalone tokens.
        let opts = SearchOptions(wholeWord: true)
        let hits = svc.scan(text: text, query: "map", options: opts)
        // Boundaries match: "map" (line 1), "mind-map" (the "map" after "-"
        // is bounded by - on left and EOL on right). Misses: "mapping",
        // "remap", "maps".
        XCTAssertEqual(hits.count, 2)
    }

    func testRegexHonoredWhenSet() {
        let svc = SearchService()
        let text = "id 123 and id 4567\nno digits here"
        let hits = svc.scan(text: text, query: #"\d+"#, options: SearchOptions(regex: true))
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].lineNumber, 1)
        XCTAssertEqual(hits[1].lineNumber, 1)
    }

    func testRegexCaseInsensitiveByDefault() {
        let svc = SearchService()
        let text = "Hello WORLD"
        let hits = svc.scan(text: text, query: "hello", options: SearchOptions(regex: true))
        XCTAssertEqual(hits.count, 1)
    }

    func testInvalidRegexReturnsNoHits() {
        let svc = SearchService()
        let hits = svc.scan(text: "anything", query: "([", options: SearchOptions(regex: true))
        XCTAssertTrue(hits.isEmpty, "malformed regex should not crash and should match nothing")
    }

    func testMaxHitsPerFileEnforced() {
        let svc = SearchService()
        let text = String(repeating: "x x x x x x x x x x\n", count: 5)
        let hits = svc.scan(text: text, query: "x", options: SearchOptions(maxHitsPerFile: 7))
        XCTAssertEqual(hits.count, 7)
    }

    /// End-to-end scan against a temp directory tree.
    func testSearchInDirectoryReturnsFilesWithHits() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("kep-search-\(UUID())")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: tmp.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "hello world\nfoo".write(to: tmp.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "no match here".write(to: tmp.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "hello again".write(to: tmp.appendingPathComponent("sub/c.md"), atomically: true, encoding: .utf8)
        // Binary-ish file should be skipped.
        try Data([0xFF, 0xFE, 0xFD]).write(to: tmp.appendingPathComponent("binary.dat"))

        let svc = SearchService()
        let results = svc.search(in: tmp, query: "hello")
        let names = results.map { $0.url.lastPathComponent }.sorted()
        XCTAssertEqual(names, ["a.md", "c.md"])
    }

    // MARK: - SearchHit.matchedSubstring (powers canvas highlight)

    func testMatchedSubstringExtractsTheRange() {
        let hit = SearchHit(lineNumber: 1, line: "the quick brown fox",
                            matchRange: NSRange(location: 4, length: 5))
        XCTAssertEqual(hit.matchedSubstring, "quick")
    }

    func testMatchedSubstringHandlesMultiByteCharacters() {
        // The NSRange must be measured in UTF-16 code units; the helper
        // converts back to String.Index correctly. Verifies CJK / non-ASCII
        // in the line doesn't desync the range.
        let line = "α β γ"
        // "γ" starts at UTF-16 offset 4 (α=1 + space=1 + β=1 + space=1).
        let hit = SearchHit(lineNumber: 1, line: line,
                            matchRange: NSRange(location: 4, length: 1))
        XCTAssertEqual(hit.matchedSubstring, "γ")
    }

    func testMatchedSubstringReturnsNilForOutOfBoundsRange() {
        let hit = SearchHit(lineNumber: 1, line: "abc",
                            matchRange: NSRange(location: 10, length: 3))
        XCTAssertNil(hit.matchedSubstring)
    }

    func testMatchedSubstringReturnsNilForEmptyMatch() {
        let hit = SearchHit(lineNumber: 1, line: "abc",
                            matchRange: NSRange(location: 0, length: 0))
        XCTAssertNil(hit.matchedSubstring)
    }
}
