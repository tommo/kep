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

    // MARK: - Free-canvas pan bounds (CanvasClipView.constrainBoundsRect)

    /// Hard-panning toward the corner must keep most of the content visible
    /// (≈ keepFraction of it), never a thin sliver — on a normal viewport.
    func testHardPanKeepsMostContentVisible() {
        let content = CGRect(x: 32, y: 32, width: 441, height: 375)
        let viewport = CGSize(width: 452, height: 617)
        let f: CGFloat = 0.6
        let corner = CanvasScroll.constrainedOrigin(
            proposed: CGPoint(x: -9999, y: -9999), viewport: viewport, content: content, keepFraction: f)
        let visibleW = (corner.x + viewport.width) - content.minX
        let expected = min(content.width, viewport.width) * f   // 441*0.6 = 264.6
        XCTAssertEqual(visibleW, expected, accuracy: 0.5, "≈60% of content stays visible")
        XCTAssertGreaterThan(visibleW, 200, "not a sliver")
    }

    /// The fixed-margin bug: under zoom the viewport shrinks; a proportional
    /// keep must still leave content visible (a fixed 120pt margin left 0).
    func testKeepIsProportionalSoZoomedViewportStillShowsContent() {
        let content = CGRect(x: 32, y: 32, width: 580, height: 990)
        let viewport = CGSize(width: 150, height: 112.5)   // 240×180 at 1.6× zoom
        let f: CGFloat = 0.6
        let corner = CanvasScroll.constrainedOrigin(
            proposed: CGPoint(x: -9999, y: -9999), viewport: viewport, content: content, keepFraction: f)
        let visW = (corner.x + viewport.width) - content.minX
        let visH = (corner.y + viewport.height) - content.minY
        XCTAssertEqual(visW, viewport.width * f, accuracy: 0.5)   // 90, not 30
        XCTAssertEqual(visH, viewport.height * f, accuracy: 0.5)  // 67.5, not 0
        XCTAssertGreaterThan(visH, 0, "content can't fully vanish vertically under zoom")
    }

    func testCanvasConstrainIsPerAxisIndependent() {
        // The X clamp must not touch Y (the original cross-axis reset bug).
        let content = CGRect(x: 0, y: 0, width: 800, height: 2000)
        let viewport = CGSize(width: 800, height: 600)
        let o = CanvasScroll.constrainedOrigin(
            proposed: CGPoint(x: 50, y: 900), viewport: viewport, content: content, keepFraction: 0.6)
        XCTAssertEqual(o.y, 900, accuracy: 1e-9, "Y preserved while X is constrained")
    }
}
