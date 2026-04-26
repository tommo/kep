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

final class MindMapCornerRadiusTests: XCTestCase {

    func testZeroPrefFallsBackToTheme() {
        XCTAssertEqual(MindMapCornerRadius.resolve(pref: 0, themeDefault: 8), 8)
    }

    func testNegativePrefFallsBackToTheme() {
        // Negative or non-finite is treated as "unset" — same as 0,
        // so a corrupt pref doesn't render circles or invert geometry.
        XCTAssertEqual(MindMapCornerRadius.resolve(pref: -3, themeDefault: 12), 12)
        XCTAssertEqual(MindMapCornerRadius.resolve(pref: .nan, themeDefault: 12), 12)
        XCTAssertEqual(MindMapCornerRadius.resolve(pref: .infinity, themeDefault: 12), 12)
    }

    func testTypicalPrefWins() {
        XCTAssertEqual(MindMapCornerRadius.resolve(pref: 16, themeDefault: 8), 16)
    }

    func testHugePrefClampsToMax() {
        // Past 32pt the rect starts looking like a pill / circle on
        // small topics — clamp so a runaway slider can't tank visual
        // identity.
        XCTAssertEqual(MindMapCornerRadius.resolve(pref: 9999, themeDefault: 8), MindMapCornerRadius.maxRadius)
    }
}
