import XCTest
@testable import MindoCore

final class MindoCoreTests: XCTestCase {
    func testApplicationSupportPathIsScoped() {
        let url = MindoCore.applicationSupportURL
        XCTAssertTrue(url.path.hasSuffix("/Mindo"))
    }
}
