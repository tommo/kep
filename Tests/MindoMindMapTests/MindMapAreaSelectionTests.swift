import XCTest
import CoreGraphics
@testable import MindoMindMap

final class MindMapAreaSelectionTests: XCTestCase {

    func testRectNormalizesRegardlessOfDirection() {
        let a = CGPoint(x: 100, y: 80)
        let b = CGPoint(x: 20, y: 10)
        let r = MindMapAreaSelection.rect(from: a, to: b)
        XCTAssertEqual(r, CGRect(x: 20, y: 10, width: 80, height: 70))
    }

    private let frames: [(id: String, rect: CGRect)] = [
        ("a", CGRect(x: 0, y: 0, width: 50, height: 20)),
        ("b", CGRect(x: 100, y: 100, width: 50, height: 20)),
        ("c", CGRect(x: 200, y: 200, width: 50, height: 20)),
    ]

    func testEnclosedByIntersection() {
        let sel = CGRect(x: 0, y: 0, width: 130, height: 130)   // catches a + b
        let hit = MindMapAreaSelection.enclosed(frames, frame: { $0.rect }, in: sel).map(\.id)
        XCTAssertEqual(hit, ["a", "b"])
    }

    func testTouchingEdgeCounts() {
        // Rect just grazes b's top-left corner → intersects → selected.
        let sel = CGRect(x: 60, y: 60, width: 45, height: 45)   // reaches x=105,y=105
        let hit = MindMapAreaSelection.enclosed(frames, frame: { $0.rect }, in: sel).map(\.id)
        XCTAssertEqual(hit, ["b"])
    }

    func testFullyContainedMode() {
        // A rect that only partially covers b is rejected in contained mode.
        let sel = CGRect(x: 90, y: 90, width: 40, height: 40)   // covers x90-130 — clips b (100-150)
        let partial = MindMapAreaSelection.enclosed(frames, frame: { $0.rect }, in: sel, fullyContained: true)
        XCTAssertTrue(partial.isEmpty)
        let whole = CGRect(x: 95, y: 95, width: 70, height: 40) // fully covers b (100-150, 100-120)
        let hit = MindMapAreaSelection.enclosed(frames, frame: { $0.rect }, in: whole, fullyContained: true).map(\.id)
        XCTAssertEqual(hit, ["b"])
    }

    func testEmptyRectSelectsNothing() {
        let sel = CGRect(x: 500, y: 500, width: 10, height: 10)
        XCTAssertTrue(MindMapAreaSelection.enclosed(frames, frame: { $0.rect }, in: sel).isEmpty)
    }
}
