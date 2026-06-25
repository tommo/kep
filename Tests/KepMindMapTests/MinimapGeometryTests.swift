import XCTest
import CoreGraphics
@testable import KepMindMap

final class MinimapGeometryTests: XCTestCase {

    func testFitScalesWorldDownToArea() {
        // 1000×500 world into a 100×100 minimap (no padding) → scale 0.1,
        // width-limited, centered vertically.
        let t = MinimapTransform(world: CGRect(x: 0, y: 0, width: 1000, height: 500),
                                 area: CGSize(width: 100, height: 100), padding: 0)
        XCTAssertEqual(t.scale, 0.1, accuracy: 0.0001)
        XCTAssertEqual(t.fitted.width, 100, accuracy: 0.01)
        XCTAssertEqual(t.fitted.height, 50, accuracy: 0.01)
        XCTAssertEqual(t.fitted.minY, 25, accuracy: 0.01, "centered vertically in the 100-tall area")
    }

    func testProjectThenUnprojectRoundTrips() {
        let t = MinimapTransform(world: CGRect(x: 200, y: 100, width: 800, height: 600),
                                 area: CGSize(width: 160, height: 120), padding: 6)
        let docPoint = CGPoint(x: 640, y: 380)
        let mini = t.project(CGRect(origin: docPoint, size: .zero)).origin
        let back = t.unproject(mini)
        XCTAssertEqual(back.x, docPoint.x, accuracy: 0.01)
        XCTAssertEqual(back.y, docPoint.y, accuracy: 0.01)
    }

    func testProjectHonorsWorldOrigin() {
        // A world not anchored at (0,0): the world's top-left maps to fitted's
        // top-left.
        let t = MinimapTransform(world: CGRect(x: 100, y: 50, width: 400, height: 400),
                                 area: CGSize(width: 100, height: 100), padding: 0)
        let topLeft = t.project(CGRect(x: 100, y: 50, width: 0, height: 0))
        XCTAssertEqual(topLeft.minX, t.fitted.minX, accuracy: 0.01)
        XCTAssertEqual(topLeft.minY, t.fitted.minY, accuracy: 0.01)
    }

    func testDegenerateWorldDoesNotDivideByZero() {
        let t = MinimapTransform(world: .zero, area: CGSize(width: 100, height: 100), padding: 6)
        XCTAssertEqual(t.scale, 1)
        // unproject must not produce NaN.
        let p = t.unproject(CGPoint(x: 10, y: 10))
        XCTAssertFalse(p.x.isNaN || p.y.isNaN)
    }

    func testCenteredOriginClampsToContent() {
        // Click near the top-left → origin clamps to (0,0).
        let o1 = MinimapGeometry.centeredOrigin(
            on: CGPoint(x: 10, y: 10),
            viewportSize: CGSize(width: 400, height: 300),
            scrollable: CGSize(width: 2000, height: 1500))
        XCTAssertEqual(o1, .zero)

        // Click in the middle → centered.
        let o2 = MinimapGeometry.centeredOrigin(
            on: CGPoint(x: 1000, y: 750),
            viewportSize: CGSize(width: 400, height: 300),
            scrollable: CGSize(width: 2000, height: 1500))
        XCTAssertEqual(o2.x, 800, accuracy: 0.01)
        XCTAssertEqual(o2.y, 600, accuracy: 0.01)

        // Click near the far corner → clamps to max scroll.
        let o3 = MinimapGeometry.centeredOrigin(
            on: CGPoint(x: 1999, y: 1499),
            viewportSize: CGSize(width: 400, height: 300),
            scrollable: CGSize(width: 2000, height: 1500))
        XCTAssertEqual(o3.x, 1600, accuracy: 0.01)
        XCTAssertEqual(o3.y, 1200, accuracy: 0.01)
    }

    func testCenteredOriginWhenContentSmallerThanViewport() {
        // Nothing to scroll — origin pinned at 0.
        let o = MinimapGeometry.centeredOrigin(
            on: CGPoint(x: 50, y: 50),
            viewportSize: CGSize(width: 800, height: 600),
            scrollable: CGSize(width: 400, height: 300))
        XCTAssertEqual(o, .zero)
    }
}
