import XCTest
@testable import MindoMindMap

final class MindMapDragGapTests: XCTestCase {

    private let ranges: [MindMapDragGap.YRange] = [
        .init(0, 20),    // sibling 0
        .init(40, 60),   // sibling 1
        .init(80, 100),  // sibling 2
    ]

    func testProbeAboveFirstReturnsZero() {
        XCTAssertEqual(MindMapDragGap.gapIndex(for: -10, sortedRanges: ranges), 0)
    }

    func testProbeBelowLastReturnsCount() {
        XCTAssertEqual(MindMapDragGap.gapIndex(for: 200, sortedRanges: ranges), 3)
    }

    func testProbeInsideTopicReturnsNil() {
        // 10 is inside the first range — drag should fall through to
        // reparent-onto-topic semantics, not gap-insert.
        XCTAssertNil(MindMapDragGap.gapIndex(for: 10, sortedRanges: ranges))
    }

    func testProbeInGapBetweenFirstAndSecondReturnsOne() {
        // Between range 0 (max 20) and range 1 (min 40).
        XCTAssertEqual(MindMapDragGap.gapIndex(for: 30, sortedRanges: ranges), 1)
    }

    func testProbeInGapBetweenSecondAndThirdReturnsTwo() {
        XCTAssertEqual(MindMapDragGap.gapIndex(for: 70, sortedRanges: ranges), 2)
    }

    func testProbeOnExactBoundaryCountsAsInsideTopic() {
        // Boundary y == range.maxY → still considered inside (>= AND <=).
        XCTAssertNil(MindMapDragGap.gapIndex(for: 20, sortedRanges: ranges))
        XCTAssertNil(MindMapDragGap.gapIndex(for: 40, sortedRanges: ranges))
    }

    func testEmptyRangesReturnsNil() {
        XCTAssertNil(MindMapDragGap.gapIndex(for: 50, sortedRanges: []))
    }

    func testSingleRangeBelowReturnsOne() {
        XCTAssertEqual(MindMapDragGap.gapIndex(for: 100, sortedRanges: [.init(0, 20)]), 1)
    }

    func testSingleRangeAboveReturnsZero() {
        XCTAssertEqual(MindMapDragGap.gapIndex(for: -100, sortedRanges: [.init(0, 20)]), 0)
    }
}
