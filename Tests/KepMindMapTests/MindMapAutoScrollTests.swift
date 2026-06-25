import XCTest
import CoreGraphics
@testable import KepMindMap

final class MindMapAutoScrollTests: XCTestCase {

    private let rect = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let margin: CGFloat = 50
    private let maxSpeed: CGFloat = 20

    private func delta(_ x: CGFloat, _ y: CGFloat) -> CGVector {
        MindMapAutoScroll.delta(point: CGPoint(x: x, y: y), visibleRect: rect,
                                margin: margin, maxSpeed: maxSpeed)
    }

    func testCenterDoesNotScroll() {
        XCTAssertEqual(delta(500, 400), .zero)
    }

    func testNearLeftScrollsLeft() {
        let d = delta(10, 400)   // 10px from left edge → deep in margin
        XCTAssertLessThan(d.dx, 0)
        XCTAssertEqual(d.dy, 0)
    }

    func testNearRightScrollsRight() {
        let d = delta(995, 400)
        XCTAssertGreaterThan(d.dx, 0)
    }

    func testNearTopScrollsUp() {
        let d = delta(500, 5)
        XCTAssertLessThan(d.dy, 0)
        XCTAssertEqual(d.dx, 0)
    }

    func testNearBottomScrollsDown() {
        let d = delta(500, 795)
        XCTAssertGreaterThan(d.dy, 0)
    }

    func testCornerScrollsBothAxes() {
        let d = delta(5, 5)
        XCTAssertLessThan(d.dx, 0)
        XCTAssertLessThan(d.dy, 0)
    }

    func testSpeedRampsUpCloserToEdge() {
        let near = delta(2, 400).dx     // very close → fast
        let far = delta(45, 400).dx     // just inside margin → slow
        XCTAssertLessThan(near, far)    // both negative; near is more negative
        XCTAssertLessThan(far, 0)
    }

    func testSpeedCapsAtMaxPastEdge() {
        // Cursor dragged past the left edge (negative x) → full speed, clamped.
        let d = delta(-100, 400)
        XCTAssertEqual(d.dx, -maxSpeed, accuracy: 0.0001)
    }

    func testExactlyAtMarginBoundaryIsZero() {
        // Distance == margin → ramp factor 0 → no scroll yet.
        XCTAssertEqual(delta(margin, 400).dx, 0, accuracy: 0.0001)
    }

    func testEmptyRectOrZeroMarginIsSafe() {
        XCTAssertEqual(MindMapAutoScroll.delta(point: .zero, visibleRect: .zero, margin: 50, maxSpeed: 20), .zero)
        XCTAssertEqual(MindMapAutoScroll.delta(point: CGPoint(x: 5, y: 5), visibleRect: rect, margin: 0, maxSpeed: 20), .zero)
    }
}
