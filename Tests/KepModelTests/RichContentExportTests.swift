import XCTest
@testable import KepModel

/// The text exporters (Markdown / Org-Mode / AsciiDoc) must carry a topic's
/// rich content — note, link, file, and code snippets — into their output,
/// not just the heading text. Built from one rich fixture so a dropped extra
/// is caught everywhere at once.
final class RichContentExportTests: XCTestCase {

    private func richMap() -> MindMap {
        let map = MindMap()
        let root = Topic(text: "Plan"); map.root = root
        let phase = root.addChild(text: "Phase 1")
        phase.setExtra(ExtraNote(text: "First note.\nSecond note line."))
        phase.setExtra(ExtraLink(uri: "https://example.com/spec"))
        phase.putCodeSnippet(language: "swift", body: "let x = 1\nprint(x)")
        let task = phase.addChild(text: "Task A")
        task.setExtra(ExtraFile(uri: "docs/taskA.pdf"))
        return map
    }

    // MARK: - Markdown

    func testMarkdownExportCarriesAllRichContent() {
        let md = MindMapMarkdownExporter.export(richMap())
        XCTAssertTrue(md.contains("# Plan"), "root heading")
        XCTAssertTrue(md.contains("## Phase 1"), "child heading")
        XCTAssertTrue(md.contains("> First note."), "note line 1 as blockquote")
        XCTAssertTrue(md.contains("> Second note line."), "note line 2 as blockquote")
        XCTAssertTrue(md.contains("[https://example.com/spec](https://example.com/spec)"), "link")
        XCTAssertTrue(md.contains("```swift\nlet x = 1\nprint(x)\n```"), "fenced code snippet")
        XCTAssertTrue(md.contains("[docs/taskA.pdf](docs/taskA.pdf)"), "file link")
    }

    // MARK: - Org-Mode

    func testOrgModeExportCarriesAllRichContent() {
        let org = OrgModeExporter.export(richMap())
        XCTAssertTrue(org.contains("* Plan"), "root heading (one star)")
        XCTAssertTrue(org.contains("** Phase 1"), "child heading (two stars)")
        XCTAssertTrue(org.contains(": First note."), "note literal line")
        XCTAssertTrue(org.contains("URL: [[https://example.com/spec]]"), "link")
        XCTAssertTrue(org.contains("FILE: [[docs/taskA.pdf]]"), "file")
        XCTAssertTrue(org.contains("#+BEGIN_SRC swift\nlet x = 1\nprint(x)\n#+END_SRC"), "code block")
    }

    // MARK: - AsciiDoc

    func testAsciiDocExportProducesHeadingsAndCarriesSnippet() {
        let adoc = AsciiDocExporter.export(richMap())
        // AsciiDoc headings use '=' levels.
        XCTAssertTrue(adoc.contains("= Plan") || adoc.contains("== Plan"), "root heading")
        XCTAssertTrue(adoc.contains("Phase 1"), "child topic present")
        XCTAssertTrue(adoc.contains("let x = 1"), "code snippet body present")
    }

    // MARK: - Heading depth past the cutoff becomes a bullet list (Markdown)

    func testMarkdownDeepLevelsBecomeBullets() {
        let map = MindMap()
        let root = Topic(text: "R"); map.root = root
        var cur = root
        for i in 1...8 { cur = cur.addChild(text: "L\(i)") }   // very deep
        let md = MindMapMarkdownExporter.export(map)
        // The deepest levels can't be headings (#######+ isn't valid), so the
        // exporter switches to an indented bullet list — assert a bullet shows.
        XCTAssertTrue(md.contains("* L"), "deep levels fall back to bullets, not endless #")
    }

    // MARK: - Empty extras are omitted, not emitted blank

    func testEmptyExtrasAreNotEmitted() {
        let map = MindMap()
        let root = Topic(text: "R"); map.root = root
        let t = root.addChild(text: "T")
        t.setExtra(ExtraNote(text: ""))            // empty note
        t.setExtra(ExtraLink(uri: ""))             // empty link
        let md = MindMapMarkdownExporter.export(map)
        XCTAssertFalse(md.contains(">\n"), "empty note must not emit a bare blockquote")
        XCTAssertFalse(md.contains("[]()"), "empty link must not emit a bare link")
    }
}
