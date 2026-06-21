import XCTest
import AppKit
@testable import MindoMindMap

final class CanvasThemeTests: XCTestCase {

    func testApplyingOverridesOnlyGivenRoles() {
        let base = MindMapTheme.light
        let t = base.applying(CanvasThemeColors(paper: "#101010", rootFill: "#FF0000"))
        XCTAssertEqual(t.paperColor.hexString, "#101010")
        XCTAssertEqual(t.rootFillColor.hexString, "#FF0000")
        // Untouched roles keep the base.
        XCTAssertEqual(t.connectorColor.hexString, base.connectorColor.hexString)
        XCTAssertEqual(t.firstLevelTextColor.hexString, base.firstLevelTextColor.hexString)
        // Non-color fields preserved.
        XCTAssertEqual(t.cornerRadius, base.cornerRadius)
    }

    func testApplyingEmptyIsIdentity() {
        let base = MindMapTheme.light
        let t = base.applying(CanvasThemeColors())
        XCTAssertEqual(t.paperColor.hexString, base.paperColor.hexString)
        XCTAssertEqual(t.rootTextColor.hexString, base.rootTextColor.hexString)
    }

    func testCanvasThemeColorsCodableRoundTrip() throws {
        let c = CanvasThemeColors(paper: "#ABCDEF", connector: "#123456")
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(CanvasThemeColors.self, from: data), c)
    }

    func testMalformedHexIgnored() {
        let base = MindMapTheme.light
        let t = base.applying(CanvasThemeColors(paper: "nope"))
        XCTAssertEqual(t.paperColor.hexString, base.paperColor.hexString)
    }
}
