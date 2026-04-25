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
}
