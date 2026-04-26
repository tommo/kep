import XCTest
import CoreGraphics
@testable import MindoMindMap

final class MindMapGridTests: XCTestCase {

    func testTypicalStepUnchanged() {
        XCTAssertEqual(MindMapGrid.normalizedStep(16), 16)
        XCTAssertEqual(MindMapGrid.normalizedStep(32), 32)
    }

    func testStepBelowFloorClampsUp() {
        // Anything under 4pt would smear into a fill at default zoom —
        // floor it so the grid stays visually a grid.
        XCTAssertEqual(MindMapGrid.normalizedStep(2), MindMapGrid.minStep)
        XCTAssertEqual(MindMapGrid.normalizedStep(0.0001), MindMapGrid.minStep)
    }

    func testStepAboveCeilingClampsDown() {
        XCTAssertEqual(MindMapGrid.normalizedStep(1024), MindMapGrid.maxStep)
    }

    func testZeroAndNegativeReturnZero() {
        // Caller treats 0 as "skip drawing entirely" — never clamp these
        // up, since the user may have explicitly wiped the pref.
        XCTAssertEqual(MindMapGrid.normalizedStep(0), 0)
        XCTAssertEqual(MindMapGrid.normalizedStep(-5), 0)
    }

    func testNonFiniteReturnsZero() {
        XCTAssertEqual(MindMapGrid.normalizedStep(.nan), 0)
        XCTAssertEqual(MindMapGrid.normalizedStep(.infinity), 0)
    }
}
