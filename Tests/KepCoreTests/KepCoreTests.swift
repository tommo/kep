import XCTest
@testable import KepCore

final class KepCoreTests: XCTestCase {
    func testApplicationSupportPathIsScoped() {
        let url = KepCore.applicationSupportURL
        XCTAssertTrue(url.path.hasSuffix("/Kep"))
    }
}
