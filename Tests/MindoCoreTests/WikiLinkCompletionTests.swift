import XCTest
@testable import MindoCore

final class WikiLinkCompletionTests: XCTestCase {

    private let docs = ["Roadmap", "Release Notes", "Ideas", "roadmap-archive", "API"]

    // MARK: - partial(inLineUpToCaret:)

    func testPartialInsideOpenLink() {
        XCTAssertEqual(WikiLinkCompletion.partial(inLineUpToCaret: "see [[Road"), "Road")
        XCTAssertEqual(WikiLinkCompletion.partial(inLineUpToCaret: "[[ Release No"), " Release No")
    }

    func testPartialEmptyRightAfterBrackets() {
        XCTAssertEqual(WikiLinkCompletion.partial(inLineUpToCaret: "intro [["), "")
    }

    func testNoOpenLink() {
        XCTAssertNil(WikiLinkCompletion.partial(inLineUpToCaret: "plain text no link"))
        XCTAssertNil(WikiLinkCompletion.partial(inLineUpToCaret: "one [ bracket"))
    }

    func testClosedLinkIsNotCompletable() {
        XCTAssertNil(WikiLinkCompletion.partial(inLineUpToCaret: "[[Roadmap]] and more"))
    }

    func testPastHeadingOrAliasSeparator() {
        XCTAssertNil(WikiLinkCompletion.partial(inLineUpToCaret: "[[Roadmap#Se"))
        XCTAssertNil(WikiLinkCompletion.partial(inLineUpToCaret: "[[Roadmap|the "))
    }

    func testUsesLastOpenBracketPair() {
        // A completed link earlier on the line doesn't shadow a later open one.
        XCTAssertEqual(WikiLinkCompletion.partial(inLineUpToCaret: "[[Done]] then [[Id"), "Id")
    }

    // MARK: - completions(forPartial:candidates:)

    func testPrefixMatchCaseInsensitiveSorted() {
        let c = WikiLinkCompletion.completions(forPartial: "r", candidates: docs)
        XCTAssertEqual(c, ["Release Notes", "Roadmap", "roadmap-archive"])
    }

    func testEmptyPartialReturnsAllSorted() {
        let c = WikiLinkCompletion.completions(forPartial: "", candidates: docs)
        XCTAssertEqual(c, ["API", "Ideas", "Release Notes", "Roadmap", "roadmap-archive"])
    }

    func testExactMatchDropped() {
        let c = WikiLinkCompletion.completions(forPartial: "ideas", candidates: docs)
        XCTAssertFalse(c.contains("Ideas"))
    }

    func testNoMatch() {
        XCTAssertTrue(WikiLinkCompletion.completions(forPartial: "zzz", candidates: docs).isEmpty)
    }

    func testDeduplicatesByName() {
        let c = WikiLinkCompletion.completions(forPartial: "a", candidates: ["API", "API", "Apex"])
        XCTAssertEqual(c, ["Apex", "API"])
    }
}
