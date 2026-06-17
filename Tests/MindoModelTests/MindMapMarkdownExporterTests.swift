import XCTest
@testable import MindoModel

final class MindMapMarkdownExporterTests: XCTestCase {

    func testEmptyMapEmitsNothing() {
        XCTAssertEqual(MindMapMarkdownExporter.export(MindMap()), "")
    }

    func testRootIsH1ChildrenIncreaseDepth() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "Alpha")
        _ = a.addChild(text: "A1")
        _ = root.addChild(text: "Beta")

        let out = MindMapMarkdownExporter.export(map)
        XCTAssertTrue(out.contains("# Root\n"))
        XCTAssertTrue(out.contains("## Alpha\n"))
        XCTAssertTrue(out.contains("### A1\n"))
        XCTAssertTrue(out.contains("## Beta\n"))
    }

    func testDeepLevelFallsBackToBullets() {
        // 5 levels of nesting → root..L4 are headings; L5 must become a
        // bullet. Mindolph applies the same cutoff so deep export still
        // renders sensibly in any markdown viewer.
        let map = MindMap()
        var node = Topic(text: "L0"); map.root = node
        for i in 1...6 { node = node.addChild(text: "L\(i)") }
        let out = MindMapMarkdownExporter.export(map)
        XCTAssertTrue(out.contains("# L0\n"))
        XCTAssertTrue(out.contains("##### L4\n"))
        XCTAssertTrue(out.contains("* L5\n"))
        XCTAssertTrue(out.contains("  * L6\n"))
    }

    func testHeadingNewlineCollapsedToSpace() {
        XCTAssertEqual(MindMapMarkdownExporter.escapeMarkdown("two\nlines"), "two lines")
    }

    func testHeadingDropsControlCharacters() {
        XCTAssertEqual(MindMapMarkdownExporter.escapeMarkdown("clean\u{07}text"), "cleantext")
    }

    func testNoteEmittedAsBlockquote() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        root.setExtra(ExtraNote(text: "first\nsecond"))
        let out = MindMapMarkdownExporter.export(map)
        XCTAssertTrue(out.contains("> first\n"))
        XCTAssertTrue(out.contains("> second\n"))
    }

    func testLinkAndFileExtrasRenderAsMarkdownLinks() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        root.setExtra(ExtraLink(uri: "https://example.com"))
        root.setExtra(ExtraFile(uri: "/tmp/foo.txt"))
        let out = MindMapMarkdownExporter.export(map)
        XCTAssertTrue(out.contains("[https://example.com](https://example.com)"))
        XCTAssertTrue(out.contains("[/tmp/foo.txt](/tmp/foo.txt)"))
    }

    func testCodeSnippetsEmittedAsFencedBlocks() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        root.putCodeSnippet(language: "swift", body: "let x = 1\n")
        let out = MindMapMarkdownExporter.export(map)
        XCTAssertTrue(out.contains("```swift\nlet x = 1\n```"))
    }

    func testCodeSnippetWithBackticksWidensFence() {
        // A snippet whose body contains a ``` run must be fenced with MORE
        // backticks so the block doesn't terminate early.
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        root.putCodeSnippet(language: "md", body: "```\ninner\n```\n")
        let out = MindMapMarkdownExporter.export(map)
        XCTAssertTrue(out.contains("````md\n"), "fence should widen to 4 backticks; got:\n\(out)")
        XCTAssertTrue(out.contains("```\ninner\n```"), "inner triple-backtick body preserved")
        // The widened fence must close the block.
        XCTAssertTrue(out.contains("````md\n```\ninner\n```\n````"))
    }

    func testCodeSnippetSortedByLanguageForStableOutput() {
        // Two snippets in non-alphabetical add order; the exporter must
        // re-sort so the output is deterministic for diffs.
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        root.putCodeSnippet(language: "swift", body: "let s = 1\n")
        root.putCodeSnippet(language: "go",    body: "x := 1\n")
        let out = MindMapMarkdownExporter.export(map)
        let goRange = out.range(of: "```go")!
        let swiftRange = out.range(of: "```swift")!
        XCTAssertLessThan(goRange.lowerBound, swiftRange.lowerBound)
    }
}
