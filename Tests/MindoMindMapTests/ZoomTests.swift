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
        let (dx, dy) = MindMapView.panOffset(deltaX: 8, deltaY: -5, precise: true)
        XCTAssertEqual(dx, 8, accuracy: 1e-9)
        XCTAssertEqual(dy, -5, accuracy: 1e-9)
    }

    func testMouseWheelPanAmplifiesLineDeltas() {
        // A coarse wheel notch (delta 1) should move a useful distance, not 1px.
        let (_, dy) = MindMapView.panOffset(deltaX: 0, deltaY: 1, precise: false)
        XCTAssertEqual(dy, 12, accuracy: 1e-9)
    }

    func testZeroDeltaPansNothing() {
        let (dx, dy) = MindMapView.panOffset(deltaX: 0, deltaY: 0, precise: true)
        XCTAssertEqual(dx, 0)
        XCTAssertEqual(dy, 0)
    }
}
