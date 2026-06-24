import XCTest
import Foundation
@testable import MindoMarkdown

/// The native swift-markdown renderer handles the constructs the hand-rolled
/// ProseMarkdown line classifier got wrong: nested/ordered lists, tables, task
/// lists, blockquotes, code fences, paragraph reflow, and inline styling.
@MainActor
final class NativeMarkdownRendererTests: XCTestCase {
    private var style: MarkdownRenderStyle { .resolved(dark: false) }

    func testOrderedAndNestedLists() {
        let blocks = NativeMarkdownRenderer.blocks("1. one\n2. two\n   - nested a\n   - nested b", style: style)
        guard case .list(let ordered, let start, let items)? = blocks.first else { return XCTFail("expected a list") }
        XCTAssertTrue(ordered)
        XCTAssertEqual(start, 1)
        XCTAssertEqual(items.count, 2)
        let hasNested = items[1].blocks.contains { if case .list(let o, _, _) = $0 { return !o } else { return false } }
        XCTAssertTrue(hasNested, "nested list must be preserved (ProseMarkdown flattened it)")
    }

    func testGFMTable() {
        let blocks = NativeMarkdownRenderer.blocks("| A | B |\n|:--|--:|\n| 1 | 2 |", style: style)
        guard case .table(let header, let rows, let align)? = blocks.first(where: {
            if case .table = $0 { return true } else { return false }
        }) else { return XCTFail("expected a table") }
        XCTAssertEqual(header.map { String($0.characters) }, ["A", "B"])
        XCTAssertEqual(rows.first?.map { String($0.characters) }, ["1", "2"])
        XCTAssertEqual(align, [.leading, .trailing])
    }

    func testTaskListCheckboxes() {
        let blocks = NativeMarkdownRenderer.blocks("- [x] done\n- [ ] todo", style: style)
        guard case .list(_, _, let items)? = blocks.first else { return XCTFail("expected a list") }
        XCTAssertEqual(items.map(\.checkbox), [true, false])
    }

    func testQuoteAndCodeFence() {
        let blocks = NativeMarkdownRenderer.blocks("> quoted\n\n```lua\nreturn 1\n```", style: style)
        XCTAssertTrue(blocks.contains { if case .quote = $0 { return true } else { return false } })
        let code = blocks.compactMap { b -> String? in
            if case .code(let lang, let text) = b { return (lang ?? "") + ":" + text } else { return nil }
        }.first
        XCTAssertEqual(code, "lua:return 1")
    }

    func testInlineStyling() {
        let blocks = NativeMarkdownRenderer.blocks("plain *em* **strong** `code` ~~gone~~", style: style)
        guard case .paragraph(let a)? = blocks.first else { return XCTFail("expected a paragraph") }
        let intents = a.runs.compactMap { $0.inlinePresentationIntent }
        XCTAssertTrue(intents.contains { $0.contains(.emphasized) })
        XCTAssertTrue(intents.contains { $0.contains(.stronglyEmphasized) })
        XCTAssertTrue(intents.contains { $0.contains(.code) })
        XCTAssertTrue(intents.contains { $0.contains(.strikethrough) })
    }

    func testParagraphReflow() {
        // soft-wrapped source lines collapse into ONE paragraph (ProseMarkdown
        // rendered each line as its own block).
        let blocks = NativeMarkdownRenderer.blocks("line one\nline two", style: style)
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let a)? = blocks.first else { return XCTFail() }
        XCTAssertEqual(String(a.characters), "line one line two")
    }

    func testHeadingsAndThematicBreak() {
        let blocks = NativeMarkdownRenderer.blocks("# Title\n\n---\n\n## Sub", style: style)
        XCTAssertEqual(blocks.compactMap { b -> Int? in
            if case .heading(let l, _) = b { return l } else { return nil }
        }, [1, 2])
        XCTAssertTrue(blocks.contains { if case .thematicBreak = $0 { return true } else { return false } })
    }
}
