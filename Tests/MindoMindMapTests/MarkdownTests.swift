// Markdown tests live alongside the mindmap test target since SPM only allows
// one test target per source target and we don't have a dedicated markdown
// test target yet. Re-export tag is fine for now.
import XCTest
import MindoMarkdown

final class MarkdownRendererTests: XCTestCase {

    func testHeadingRendersAsHTML() {
        let html = MarkdownRenderer.renderBody(markdown: "# Title")
        XCTAssertTrue(html.contains("<h1>"), "got: \(html)")
        XCTAssertTrue(html.contains("Title"))
    }

    func testListRendersAsHTML() {
        let html = MarkdownRenderer.renderBody(markdown: """
        - one
        - two
        - three
        """)
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertEqual(html.components(separatedBy: "<li>").count - 1, 3)
    }

    func testCodeBlockPreservesContent() {
        let html = MarkdownRenderer.renderBody(markdown: """
        ```swift
        let x = 1
        ```
        """)
        XCTAssertTrue(html.contains("<pre>"))
        XCTAssertTrue(html.contains("let x = 1"))
    }

    func testFullDocumentIncludesStylesheet() {
        let html = MarkdownRenderer.render(markdown: "**bold**")
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
    }
}
