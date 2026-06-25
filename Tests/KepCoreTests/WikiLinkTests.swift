import XCTest
@testable import KepCore

final class WikiLinkTests: XCTestCase {

    func testParsesPlainTargetHeadingAlias() {
        let text = "See [[Notes]], [[Roadmap#Q3]] and [[data.csv|the data]]."
        let links = WikiLinkParser.links(in: text)
        XCTAssertEqual(links.count, 3)
        XCTAssertEqual(links[0].target, "Notes")
        XCTAssertNil(links[0].heading); XCTAssertNil(links[0].alias)
        XCTAssertEqual(links[1].target, "Roadmap")
        XCTAssertEqual(links[1].heading, "Q3")
        XCTAssertEqual(links[2].target, "data.csv")
        XCTAssertEqual(links[2].alias, "the data")
        XCTAssertEqual(links[2].displayText, "the data")
    }

    func testInDocumentHeadingLink() {
        let links = WikiLinkParser.links(in: "jump to [[#Summary]]")
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].target, "")
        XCTAssertEqual(links[0].heading, "Summary")
        XCTAssertEqual(links[0].displayText, "#Summary")
    }

    func testIgnoresEmptyAndUnclosed() {
        XCTAssertTrue(WikiLinkParser.links(in: "[[]] and [[ | ]] and [[unclosed").isEmpty)
    }

    func testNSRangeCoversWholeToken() {
        let text = "x [[Notes]] y"
        let r = WikiLinkParser.links(in: text)[0].nsRange
        XCTAssertEqual((text as NSString).substring(with: r), "[[Notes]]")
    }

    // MARK: - Resolver

    private let files = [
        URL(fileURLWithPath: "/ws/Notes.md"),
        URL(fileURLWithPath: "/ws/docs/Roadmap.md"),
        URL(fileURLWithPath: "/ws/data.csv"),
        URL(fileURLWithPath: "/ws/deep/a/b/Notes.md"),
    ]

    func testResolveBaseNameCaseInsensitive() {
        XCTAssertEqual(WikiLinkResolver.resolve("roadmap", in: files)?.lastPathComponent, "Roadmap.md")
    }

    func testResolveExactNameWithExtension() {
        XCTAssertEqual(WikiLinkResolver.resolve("data.csv", in: files)?.lastPathComponent, "data.csv")
    }

    func testResolveAmbiguousPrefersShortestPath() {
        // Two Notes.md — the one closer to the root (shorter path) wins.
        XCTAssertEqual(WikiLinkResolver.resolve("Notes", in: files)?.path, "/ws/Notes.md")
    }

    func testResolveNoMatch() {
        XCTAssertNil(WikiLinkResolver.resolve("Missing", in: files))
        XCTAssertNil(WikiLinkResolver.resolve("", in: files))
    }
}
