import XCTest
@testable import KepMarkdown

final class MarkdownLinkPolicyTests: XCTestCase {

    func testNonClickNavigationAlwaysAllowed() {
        // The initial loadHTMLString / reload / JS scroll arrive as non-link
        // navigations and must render in place.
        let action = MarkdownLinkPolicy.decide(
            url: URL(string: "https://example.com"), isLinkActivation: false)
        XCTAssertEqual(action, .allow)
    }

    func testNilURLAllowed() {
        XCTAssertEqual(MarkdownLinkPolicy.decide(url: nil, isLinkActivation: true), .allow)
    }

    func testHTTPLinkOpensExternally() {
        let url = URL(string: "https://example.com/page")!
        XCTAssertEqual(
            MarkdownLinkPolicy.decide(url: url, isLinkActivation: true),
            .openExternally(url))
    }

    func testHTTPSchemeOpensExternally() {
        let url = URL(string: "http://example.com")!
        XCTAssertEqual(
            MarkdownLinkPolicy.decide(url: url, isLinkActivation: true),
            .openExternally(url))
    }

    func testMailtoOpensExternally() {
        let url = URL(string: "mailto:a@b.com")!
        XCTAssertEqual(
            MarkdownLinkPolicy.decide(url: url, isLinkActivation: true),
            .openExternally(url))
    }

    func testFileSchemeOpensFile() {
        let url = URL(string: "file:///Users/me/notes/other.md")!
        XCTAssertEqual(
            MarkdownLinkPolicy.decide(url: url, isLinkActivation: true),
            .openFile(url))
    }

    func testRelativeLinkWithoutSchemeOpensFile() {
        // A relative markdown link like [x](other.md) arrives scheme-less.
        let url = URL(string: "other.md")!
        XCTAssertEqual(
            MarkdownLinkPolicy.decide(url: url, isLinkActivation: true),
            .openFile(url))
    }

    func testPureFragmentAnchorAllowed() {
        // Table-of-contents "#section" should scroll the preview, not leave.
        let url = URL(string: "#section-2")!
        XCTAssertEqual(
            MarkdownLinkPolicy.decide(url: url, isLinkActivation: true),
            .allow)
    }

    func testUnknownSchemeOpensExternallyRatherThanClobberingPreview() {
        let url = URL(string: "obsidian://open?vault=x")!
        XCTAssertEqual(
            MarkdownLinkPolicy.decide(url: url, isLinkActivation: true),
            .openExternally(url))
    }
}

final class MarkdownPreviewBaseTests: XCTestCase {

    func testNilDocumentYieldsNilBase() {
        XCTAssertNil(MarkdownPreviewBase.baseURL(forDocumentAt: nil))
    }

    func testBaseURLIsDocumentDirectory() {
        let doc = URL(fileURLWithPath: "/Users/me/notes/journal.md")
        let base = MarkdownPreviewBase.baseURL(forDocumentAt: doc)
        XCTAssertEqual(base?.path, "/Users/me/notes")
    }

    func testRelativeImageResolvesAgainstBase() {
        // The whole point: ![](images/x.png) must resolve to a sibling path.
        let doc = URL(fileURLWithPath: "/Users/me/notes/journal.md")
        let base = MarkdownPreviewBase.baseURL(forDocumentAt: doc)!
        let resolved = URL(string: "images/x.png", relativeTo: base)!
        XCTAssertEqual(resolved.absoluteURL.path, "/Users/me/notes/images/x.png")
    }

    func testNestedDirectoryPreserved() {
        let doc = URL(fileURLWithPath: "/a/b/c/d.md")
        XCTAssertEqual(MarkdownPreviewBase.baseURL(forDocumentAt: doc)?.path, "/a/b/c")
    }
}
