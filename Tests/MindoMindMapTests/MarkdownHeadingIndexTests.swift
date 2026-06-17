import XCTest
@testable import MindoMarkdown

final class MarkdownHeadingIndexTests: XCTestCase {

    private let doc = """
    # Title

    Intro paragraph.

    ## Q3 Plans
    body

    ### Sub Section
    more
    """

    func testFindsHeadingByteOffset() {
        // "## Q3 Plans" starts after "# Title\n\nIntro paragraph.\n\n".
        let prefix = "# Title\n\nIntro paragraph.\n\n"
        XCTAssertEqual(MarkdownHeadingIndex.byteOffset(forHeading: "Q3 Plans", in: doc), prefix.utf8.count)
    }

    func testSlugMatchIsLenient() {
        // Different case / punctuation still resolves via slug.
        XCTAssertEqual(MarkdownHeadingIndex.byteOffset(forHeading: "q3-plans", in: doc),
                       MarkdownHeadingIndex.byteOffset(forHeading: "Q3 Plans", in: doc))
    }

    func testTopHeadingAtZero() {
        XCTAssertEqual(MarkdownHeadingIndex.byteOffset(forHeading: "Title", in: doc), 0)
    }

    func testMissingHeadingReturnsNil() {
        XCTAssertNil(MarkdownHeadingIndex.byteOffset(forHeading: "Nonexistent", in: doc))
        XCTAssertNil(MarkdownHeadingIndex.byteOffset(forHeading: "", in: doc))
    }

    func testNonHeadingHashNotMatched() {
        // A '#' not followed by space isn't a heading.
        XCTAssertNil(MarkdownHeadingIndex.byteOffset(forHeading: "hashtag", in: "#hashtag not a heading"))
    }
}
