import XCTest
@testable import MindoPlantUML

final class PlantUMLPreviewStateTests: XCTestCase {

    private let good = Data([1, 2, 3])
    private let newer = Data([4, 5, 6])

    // MARK: - Cache retention (the "failed render wiped the good SVG" bug)

    func testSuccessfulRenderReplacesCache() {
        XCTAssertEqual(PlantUMLPreviewState.updatedCache(current: good, rendered: newer), newer)
    }

    func testFailedRenderKeepsLastGoodCache() {
        XCTAssertEqual(PlantUMLPreviewState.updatedCache(current: good, rendered: nil), good)
    }

    func testFailedRenderWithNoPriorCacheStaysNil() {
        XCTAssertNil(PlantUMLPreviewState.updatedCache(current: nil, rendered: nil))
    }

    func testFirstSuccessfulRenderPopulatesEmptyCache() {
        XCTAssertEqual(PlantUMLPreviewState.updatedCache(current: nil, rendered: newer), newer)
    }

    // MARK: - Re-render trigger (rank 20 dark-mode bug)

    func testRerendersOnTextChange() {
        XCTAssertTrue(PlantUMLPreviewState.shouldRerender(textChanged: true, darkModeChanged: false))
    }

    func testRerendersOnDarkModeFlip() {
        XCTAssertTrue(PlantUMLPreviewState.shouldRerender(textChanged: false, darkModeChanged: true))
    }

    func testNoRerenderWhenNothingChanged() {
        XCTAssertFalse(PlantUMLPreviewState.shouldRerender(textChanged: false, darkModeChanged: false))
    }

    // MARK: - Copy outcome (the silent no-op bug)

    func testCopyWithRenderedDataSucceeds() {
        XCTAssertEqual(PlantUMLClipboard.outcome(for: good), .copied)
    }

    func testCopyWithNoDataReportsNothing() {
        XCTAssertEqual(PlantUMLClipboard.outcome(for: nil), .nothingToCopy)
    }

    func testCopyWithEmptyDataReportsNothing() {
        XCTAssertEqual(PlantUMLClipboard.outcome(for: Data()), .nothingToCopy)
    }
}
