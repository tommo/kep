import XCTest
@testable import KepCore

final class FileLinkSearchTests: XCTestCase {
    private func u(_ p: String) -> URL { URL(fileURLWithPath: p) }

    func testFindsRelativeMarkdownLinkAndImage() {
        let target = u("/ws/img/diagram.png")
        let corpus: [(url: URL, text: String)] = [
            (u("/ws/notes.md"), "See ![the diagram](img/diagram.png) above."),
            (u("/ws/sub/page.md"), "Ref [up](../img/diagram.png)."),
            (u("/ws/other.md"), "No link here."),
        ]
        let refs = FileLinkSearch.referencing(target, corpus: corpus)
        XCTAssertEqual(refs.map { $0.source.lastPathComponent }, ["notes.md", "page.md"])
        XCTAssertEqual(refs[0].snippets.first, "See ![the diagram](img/diagram.png) above.")
    }

    func testIgnoresExternalAnchorAndSelf() {
        let target = u("/ws/a.md")
        let corpus: [(url: URL, text: String)] = [
            (u("/ws/a.md"), "[self](a.md)"),                 // self — skipped
            (u("/ws/b.md"), "[ext](https://x.com/a.md) [anchor](#a.md) [m](mailto:a.md)"),
            (u("/ws/c.md"), "[real](a.md)"),
        ]
        let refs = FileLinkSearch.referencing(target, corpus: corpus)
        XCTAssertEqual(refs.map { $0.source.lastPathComponent }, ["c.md"])
    }

    func testStripsTitleFragmentAndQuery() {
        let target = u("/ws/doc.md")
        let corpus: [(url: URL, text: String)] = [
            (u("/ws/x.md"), #"[t](doc.md "a title")"#),
            (u("/ws/y.md"), "[t](doc.md#section)"),
        ]
        let refs = FileLinkSearch.referencing(target, corpus: corpus)
        XCTAssertEqual(Set(refs.map { $0.source.lastPathComponent }), ["x.md", "y.md"])
    }

    func testResolveRejectsExternalAndAnchors() {
        let base = URL(fileURLWithPath: "/ws", isDirectory: true)
        XCTAssertNil(FileLinkSearch.resolve("https://x.com/a", relativeTo: base))
        XCTAssertNil(FileLinkSearch.resolve("#heading", relativeTo: base))
        XCTAssertNil(FileLinkSearch.resolve("", relativeTo: base))
        XCTAssertEqual(FileLinkSearch.resolve("sub/a.md", relativeTo: base)?.standardizedFileURL.path,
                       "/ws/sub/a.md")
    }
}
