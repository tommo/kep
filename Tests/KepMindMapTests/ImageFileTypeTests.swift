import XCTest
@testable import KepCore

final class ImageFileTypeTests: XCTestCase {
    // ImageFileView lives in the app target; mirror its extension set here via
    // SupportedFileType where they overlap, and assert the classifier basics.
    func testSupportedImageClassification() {
        XCTAssertTrue(SupportedFileType.classify(name: "a.png")?.isImage ?? false)
        XCTAssertTrue(SupportedFileType.classify(name: "a.jpg")?.isImage ?? false)
        XCTAssertFalse(SupportedFileType.classify(name: "a.md")?.isImage ?? false)
        XCTAssertNil(SupportedFileType.classify(name: "a.gif"))  // not a routed editor type
    }
}
