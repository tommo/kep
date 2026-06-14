import XCTest
@testable import MindoMindMap

final class ZoomMathTests: XCTestCase {

    func testZoomInScalesUpBoundedByMax() {
        let next = MindMapView.clampedZoom(current: 1.0, factor: 1.25, min: 0.25, max: 3.0)
        XCTAssertEqual(next, 1.25, accuracy: 1e-9)
    }

    func testZoomOutScalesDownBoundedByMin() {
        let next = MindMapView.clampedZoom(current: 1.0, factor: 1.0 / 1.25, min: 0.25, max: 3.0)
        XCTAssertEqual(next, 0.8, accuracy: 1e-9)
    }

    func testZoomClampsToMaxWhenExceeded() {
        let next = MindMapView.clampedZoom(current: 2.8, factor: 2.0, min: 0.25, max: 3.0)
        XCTAssertEqual(next, 3.0, accuracy: 1e-9)
    }

    func testZoomClampsToMinWhenExceeded() {
        let next = MindMapView.clampedZoom(current: 0.3, factor: 0.5, min: 0.25, max: 3.0)
        XCTAssertEqual(next, 0.25, accuracy: 1e-9)
    }

    func testNoOpFactorPreservesCurrent() {
        let next = MindMapView.clampedZoom(current: 1.42, factor: 1.0, min: 0.25, max: 3.0)
        XCTAssertEqual(next, 1.42, accuracy: 1e-9)
    }

    // MARK: - Zoom-to-fit math

    func testFitMagnificationPicksTighterAxis() {
        // Wide content (1000x500) into a square viewport (400x400):
        // width-fit = 0.4, height-fit = 0.8 → tightest = 0.4.
        let mag = MindMapView.fitMagnification(
            visible: CGSize(width: 400, height: 400),
            content: CGSize(width: 1000, height: 500),
            min: 0.25, max: 3.0
        )
        XCTAssertEqual(mag, 0.4, accuracy: 1e-9)
    }

    func testFitMagnificationClampsBelowMin() {
        let mag = MindMapView.fitMagnification(
            visible: CGSize(width: 100, height: 100),
            content: CGSize(width: 10000, height: 10000),
            min: 0.25, max: 3.0
        )
        XCTAssertEqual(mag, 0.25, accuracy: 1e-9)
    }

    func testFitMagnificationClampsAboveMax() {
        let mag = MindMapView.fitMagnification(
            visible: CGSize(width: 4000, height: 4000),
            content: CGSize(width: 100, height: 100),
            min: 0.25, max: 3.0
        )
        XCTAssertEqual(mag, 3.0, accuracy: 1e-9)
    }

    func testFitMagnificationReturnsOneOnEmptyContent() {
        let mag = MindMapView.fitMagnification(
            visible: CGSize(width: 400, height: 400),
            content: .zero,
            min: 0.25, max: 3.0
        )
        XCTAssertEqual(mag, 1.0)
    }

    // MARK: - Pinch composition (NSEvent.magnification is a delta)

    func testPinchPositiveDeltaScalesUp() {
        // A +0.10 trackpad delta against current 1.0 → factor 1.10 → 1.10.
        let next = MindMapView.clampedZoom(current: 1.0, factor: 1 + 0.10, min: 0.25, max: 3.0)
        XCTAssertEqual(next, 1.10, accuracy: 1e-9)
    }

    func testPinchNegativeDeltaScalesDown() {
        let next = MindMapView.clampedZoom(current: 1.0, factor: 1 + (-0.20), min: 0.25, max: 3.0)
        XCTAssertEqual(next, 0.80, accuracy: 1e-9)
    }

    func testPinchAccumulatedDeltasClampAtMax() {
        // Simulate three large outward pinches in a row — should cap at max.
        var current: CGFloat = 2.5
        for _ in 0..<3 {
            current = MindMapView.clampedZoom(current: current, factor: 1 + 0.5, min: 0.25, max: 3.0)
        }
        XCTAssertEqual(current, 3.0, accuracy: 1e-9)
    }

    func testPinchAccumulatedDeltasClampAtMin() {
        var current: CGFloat = 0.5
        for _ in 0..<3 {
            current = MindMapView.clampedZoom(current: current, factor: 1 + (-0.5), min: 0.25, max: 3.0)
        }
        XCTAssertEqual(current, 0.25, accuracy: 1e-9)
    }

    // MARK: - Scroll-to-pan offset

    func testTrackpadPanPassesDeltasThrough() {
        let (dx, dy) = MindMapView.panOffset(
            scrollingDeltaX: 8, scrollingDeltaY: -5, precise: true, shiftHeld: false)
        XCTAssertEqual(dx, 8, accuracy: 1e-9)
        XCTAssertEqual(dy, -5, accuracy: 1e-9)
    }

    func testMouseWheelPanAmplifiesLineDeltas() {
        // A coarse wheel notch (delta 1) should move a useful distance, not 1px.
        let (_, dy) = MindMapView.panOffset(
            scrollingDeltaX: 0, scrollingDeltaY: 1, precise: false, shiftHeld: false)
        XCTAssertEqual(dy, 12, accuracy: 1e-9)
    }

    func testShiftWheelPansHorizontally() {
        // Mouse wheel + Shift: the (vertical) wheel delta becomes a horizontal
        // pan. Amplified like any wheel notch.
        let (dx, dy) = MindMapView.panOffset(
            scrollingDeltaX: 0, scrollingDeltaY: 2, precise: false, shiftHeld: true)
        XCTAssertEqual(dx, 24, accuracy: 1e-9, "wheel delta moved to the X axis")
        XCTAssertEqual(dy, 0, accuracy: 1e-9)
    }

    func testShiftDoesNotDoubleSwapWhenPlatformAlreadyHorizontal() {
        // If the platform already put the delta on X, Shift must not move it back.
        let (dx, dy) = MindMapView.panOffset(
            scrollingDeltaX: 5, scrollingDeltaY: 0, precise: true, shiftHeld: true)
        XCTAssertEqual(dx, 5, accuracy: 1e-9)
        XCTAssertEqual(dy, 0, accuracy: 1e-9)
    }

    func testZeroDeltaPansNothing() {
        let (dx, dy) = MindMapView.panOffset(
            scrollingDeltaX: 0, scrollingDeltaY: 0, precise: true, shiftHeld: false)
        XCTAssertEqual(dx, 0)
        XCTAssertEqual(dy, 0)
    }

    // MARK: - Per-axis pan clamping (regression: X scroll reset Y offset)

    func testPanningXDoesNotResetYWhenXAxisHasNoRoom() {
        // Tall, narrow content: viewport is as wide as the doc (no X room) but
        // shorter (Y room). Already scrolled down to y=100. A horizontal scroll
        // must leave y untouched — the bug zeroed it.
        let doc = CGSize(width: 800, height: 2000)
        let viewport = CGSize(width: 800, height: 600)
        let origin = MindMapView.pannedOrigin(
            current: CGPoint(x: 0, y: 100), dx: 30, dy: 0,
            docSize: doc, viewportSize: viewport)
        XCTAssertEqual(origin.x, 0, accuracy: 1e-9, "no X room → x pinned at 0")
        XCTAssertEqual(origin.y, 100, accuracy: 1e-9, "Y offset preserved across an X pan")
    }

    func testPanClampsToScrollableRangePerAxis() {
        let doc = CGSize(width: 2000, height: 1500)
        let viewport = CGSize(width: 400, height: 300)
        // Push past the far edge on both axes → clamp to (doc − viewport).
        let far = MindMapView.pannedOrigin(
            current: CGPoint(x: 1500, y: 1100), dx: -1000, dy: -1000,
            docSize: doc, viewportSize: viewport)
        XCTAssertEqual(far.x, 1600, accuracy: 1e-9)
        XCTAssertEqual(far.y, 1200, accuracy: 1e-9)
        // Push past the near edge → clamp to 0.
        let near = MindMapView.pannedOrigin(
            current: CGPoint(x: 50, y: 50), dx: 1000, dy: 1000,
            docSize: doc, viewportSize: viewport)
        XCTAssertEqual(near, .zero)
    }

    func testPanIndependentAxesBothMove() {
        let doc = CGSize(width: 2000, height: 1500)
        let viewport = CGSize(width: 400, height: 300)
        let o = MindMapView.pannedOrigin(
            current: CGPoint(x: 500, y: 500), dx: -20, dy: -10,
            docSize: doc, viewportSize: viewport)
        XCTAssertEqual(o.x, 520, accuracy: 1e-9)
        XCTAssertEqual(o.y, 510, accuracy: 1e-9)
    }
}
