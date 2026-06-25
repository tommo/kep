import XCTest
@testable import KepBase

final class OutlineMarkdownTests: XCTestCase {

    func testExtractsHeadings() {
        let md = """
        # Title
        Some text.

        ## Section A
        body
        ### Subsection
        ## Section B
        """
        let items = Outline.fromMarkdown(md)
        XCTAssertEqual(items.map(\.title), ["Title", "Section A", "Subsection", "Section B"])
        XCTAssertEqual(items.map(\.depth), [1, 2, 3, 2])
    }

    func testIgnoresNonHeadingLines() {
        let md = "regular text\n#nottitle without space\nactually `not # heading`\n"
        XCTAssertTrue(Outline.fromMarkdown(md).isEmpty)
    }

    func testTargetIsByteOffset() {
        let md = "intro\n\n## After Two Lines\n"
        let items = Outline.fromMarkdown(md)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.target, "7")  // "intro\n\n" = 7 bytes
    }

    func testEmptyInputProducesNoItems() {
        XCTAssertTrue(Outline.fromMarkdown("").isEmpty)
    }
}
