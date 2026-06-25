import XCTest
@testable import KepCore

final class TabReorderTests: XCTestCase {

    func testMoveLaterTabEarlier() {
        // Drag "C" onto "A" (drag-left) — C lands at A's slot, A shifts right.
        let result = TabReorder.move(["A", "B", "C", "D"], from: "C", to: "A")
        XCTAssertEqual(result, ["C", "A", "B", "D"])
    }

    func testMoveEarlierTabLater() {
        // Drag "A" onto "C" (drag-right) — A lands *after* C, C shifts left to
        // fill the gap. Net effect: ["B", "C", "A", "D"].
        let result = TabReorder.move(["A", "B", "C", "D"], from: "A", to: "C")
        XCTAssertEqual(result, ["B", "C", "A", "D"])
    }

    func testMoveAdjacentTabs() {
        let result = TabReorder.move(["A", "B"], from: "A", to: "B")
        XCTAssertEqual(result, ["B", "A"])
    }

    func testMoveOntoSelfIsNoOp() {
        let result = TabReorder.move(["A", "B", "C"], from: "B", to: "B")
        XCTAssertEqual(result, ["A", "B", "C"])
    }

    func testMissingSourceLeavesArrayUntouched() {
        let result = TabReorder.move(["A", "B"], from: "X", to: "A")
        XCTAssertEqual(result, ["A", "B"])
    }

    func testMissingTargetLeavesArrayUntouched() {
        let result = TabReorder.move(["A", "B"], from: "A", to: "X")
        XCTAssertEqual(result, ["A", "B"])
    }

    func testMoveToEndOfList() {
        // B onto D (drag-right) → B lands past D's old slot.
        let result = TabReorder.move(["A", "B", "C", "D"], from: "B", to: "D")
        XCTAssertEqual(result, ["A", "C", "D", "B"])
    }

    func testMoveToCollectionInsertionBoundary() {
        XCTAssertEqual(
            TabReorder.move(["A", "B", "C", "D"], from: "A", toInsertionIndex: 3),
            ["B", "C", "A", "D"]
        )
        XCTAssertEqual(
            TabReorder.move(["A", "B", "C", "D"], from: "C", toInsertionIndex: 0),
            ["C", "A", "B", "D"]
        )
    }

    func testMoveToCollectionEndBoundary() {
        XCTAssertEqual(
            TabReorder.move(["A", "B", "C"], from: "A", toInsertionIndex: 3),
            ["B", "C", "A"]
        )
    }

    func testMoveToOwnAdjacentBoundaryIsNoOp() {
        XCTAssertEqual(
            TabReorder.move(["A", "B", "C"], from: "B", toInsertionIndex: 2),
            ["A", "B", "C"]
        )
    }
}
