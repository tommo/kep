import XCTest
@testable import MindoMarkdown

final class MarkdownViewModeTests: XCTestCase {

    func testEditorShowsOnlyEditor() {
        XCTAssertTrue(MarkdownViewMode.editor.showsEditor)
        XCTAssertFalse(MarkdownViewMode.editor.showsPreview)
    }

    func testPreviewShowsOnlyPreview() {
        XCTAssertFalse(MarkdownViewMode.preview.showsEditor)
        XCTAssertTrue(MarkdownViewMode.preview.showsPreview)
    }

    func testSplitShowsBoth() {
        XCTAssertTrue(MarkdownViewMode.split.showsEditor)
        XCTAssertTrue(MarkdownViewMode.split.showsPreview)
    }

    func testFromRawValueRoundTrips() {
        for mode in MarkdownViewMode.allCases {
            XCTAssertEqual(MarkdownViewMode.from(rawValue: mode.rawValue), mode)
        }
    }

    func testFromUnknownOrNilFallsBackToEditor() {
        // The single live-styled pane is the modern default; the HTML preview
        // is opt-in via the footer switch.
        XCTAssertEqual(MarkdownViewMode.from(rawValue: nil), .editor)
        XCTAssertEqual(MarkdownViewMode.from(rawValue: ""), .editor)
        XCTAssertEqual(MarkdownViewMode.from(rawValue: "bogus"), .editor)
    }

    func testEveryModeHasDistinctSymbolAndTooltip() {
        let symbols = MarkdownViewMode.allCases.map { $0.symbolName }
        let tooltips = MarkdownViewMode.allCases.map { $0.tooltip }
        XCTAssertEqual(Set(symbols).count, MarkdownViewMode.allCases.count)
        XCTAssertEqual(Set(tooltips).count, MarkdownViewMode.allCases.count)
    }
}
