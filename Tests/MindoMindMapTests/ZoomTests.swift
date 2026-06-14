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

    // MARK: - Free-canvas pan bounds (CanvasClipView.constrainBoundsRect)

    func testViewportCannotParkOnEmptyCanvasAwayFromContent() {
        // The bug: content sits in part of a larger document; the viewport got
        // stuck in the empty padding. Constraining against the CONTENT rect
        // pulls a far-away proposed origin back so content stays visible.
        let content = CGRect(x: 500, y: 400, width: 300, height: 300)
        let viewport = CGSize(width: 400, height: 300)
        let keep: CGFloat = 96
        // Proposing the top-left empty corner (0,0) must snap to where content
        // is at least `keep` visible — i.e. origin ≥ content.minX + keep - vp.
        let o = CanvasScroll.constrainedOrigin(
            proposed: .zero, viewport: viewport, content: content, keepVisible: keep)
        XCTAssertEqual(o.x, content.minX + keep - viewport.width, accuracy: 1e-9) // 500+96-400 = 196
        XCTAssertEqual(o.y, content.minY + keep - viewport.height, accuracy: 1e-9) // 400+96-300 = 196
        // At that origin, the viewport really does overlap content by keep.
        let visibleRight = o.x + viewport.width
        XCTAssertGreaterThanOrEqual(visibleRight - content.minX, keep - 1e-6)
    }

    func testCanvasOverPanKeepsContentVisibleAtExtremes() {
        let content = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let viewport = CGSize(width: 400, height: 300)
        let keep: CGFloat = 96
        let near = CanvasScroll.constrainedOrigin(
            proposed: CGPoint(x: -9999, y: -9999), viewport: viewport, content: content, keepVisible: keep)
        XCTAssertEqual(near.x, keep - viewport.width, accuracy: 1e-9)   // -304
        XCTAssertEqual(near.y, keep - viewport.height, accuracy: 1e-9)  // -204
        let far = CanvasScroll.constrainedOrigin(
            proposed: CGPoint(x: 9999, y: 9999), viewport: viewport, content: content, keepVisible: keep)
        XCTAssertEqual(far.x, content.width - keep, accuracy: 1e-9)   // 904
        XCTAssertEqual(far.y, content.height - keep, accuracy: 1e-9)  // 704
    }

    func testCanvasConstrainIsPerAxisIndependent() {
        // The X clamp must not touch Y (the original cross-axis reset bug).
        let content = CGRect(x: 0, y: 0, width: 800, height: 2000)
        let viewport = CGSize(width: 800, height: 600)
        let o = CanvasScroll.constrainedOrigin(
            proposed: CGPoint(x: 50, y: 900), viewport: viewport, content: content, keepVisible: 96)
        XCTAssertEqual(o.y, 900, accuracy: 1e-9, "Y preserved while X is constrained")
    }
}
