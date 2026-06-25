import XCTest
@testable import KepCore

final class WikiLinkMarkdownTests: XCTestCase {

    func testLinkifyPlainAliasAndHeading() {
        let out = WikiLinkMarkdown.linkify("see [[Roadmap]] and [[Plan|the plan]] and [[Doc#Sec]]")
        XCTAssertTrue(out.contains("[Roadmap](kep-wiki:Roadmap)"), out)
        XCTAssertTrue(out.contains("[the plan](kep-wiki:Plan)"), out)
        XCTAssertTrue(out.contains("[Doc#Sec](kep-wiki:Doc#Sec)"), out)
    }

    func testLinkifyPercentEncodesSpaces() {
        let out = WikiLinkMarkdown.linkify("open [[Brewing Process]]")
        XCTAssertTrue(out.contains("(kep-wiki:Brewing%20Process)"), out)
        XCTAssertTrue(out.contains("[Brewing Process]"), out)
    }

    func testInDocLinkLeftAlone() {
        let out = WikiLinkMarkdown.linkify("jump to [[#Section]] here")
        XCTAssertEqual(out, "jump to [[#Section]] here")
    }

    func testNoLinksUnchanged() {
        XCTAssertEqual(WikiLinkMarkdown.linkify("plain text"), "plain text")
    }

    func testDecodeRoundTrip() {
        XCTAssertEqual(WikiLinkMarkdown.decode("kep-wiki:Roadmap")?.target, "Roadmap")
        let d = WikiLinkMarkdown.decode("kep-wiki:Brewing%20Process#Q3")
        XCTAssertEqual(d?.target, "Brewing Process")
        XCTAssertEqual(d?.heading, "Q3")
        XCTAssertNil(WikiLinkMarkdown.decode("https://example.com"))
    }
}
