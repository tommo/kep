import XCTest
@testable import MindoMarkdown

final class ScrollSyncScriptTests: XCTestCase {

    /// The full document body should embed the shim inside a <script> tag.
    func testRenderedDocumentEmbedsScript() {
        let html = MarkdownRenderer.render(markdown: "# Hi")
        XCTAssertTrue(html.contains("<script>"))
        XCTAssertTrue(html.contains("mindoScrollTo"))
    }

    /// `renderBody` is the embeddable variant — it should NOT include the
    /// `<style>`/`<script>` chrome.
    func testRenderBodyOmitsChrome() {
        let body = MarkdownRenderer.renderBody(markdown: "# Hi")
        XCTAssertFalse(body.contains("<style>"))
        XCTAssertFalse(body.contains("<script>"))
        XCTAssertTrue(body.contains("<h1>Hi</h1>"))
    }
}
