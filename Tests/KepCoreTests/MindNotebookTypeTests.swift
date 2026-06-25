import XCTest
@testable import KepCore

final class MindNotebookTypeTests: XCTestCase {
    func testMnbClassifies() {
        XCTAssertEqual(SupportedFileType.classify(name: "research.mnb"), .mindNotebook)
        XCTAssertEqual(SupportedFileType.classify(url: URL(fileURLWithPath: "/x/research.mnb")), .mindNotebook)
    }

    func testMnbIsTextWithSymbol() {
        XCTAssertTrue(SupportedFileType.mindNotebook.isText)
        XCTAssertFalse(SupportedFileType.mindNotebook.isImage)
        XCTAssertEqual(SupportedFileType.mindNotebook.sfSymbolName, "text.book.closed")
        XCTAssertEqual(SupportedFileType.mindNotebook.rawValue, "mnb")
    }
}
