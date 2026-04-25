import XCTest
@testable import MindoCore

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

    func testMaxHitsPerFileEnforced() {
        let svc = SearchService()
        let text = String(repeating: "x x x x x x x x x x\n", count: 5)
        let hits = svc.scan(text: text, query: "x", options: SearchOptions(maxHitsPerFile: 7))
        XCTAssertEqual(hits.count, 7)
    }

    /// End-to-end scan against a temp directory tree.
    func testSearchInDirectoryReturnsFilesWithHits() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("mindo-search-\(UUID())")
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
}
