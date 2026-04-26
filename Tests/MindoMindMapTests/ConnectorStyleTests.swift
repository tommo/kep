import XCTest
@testable import MindoMindMap

final class ConnectorStyleTests: XCTestCase {

    func testParseBezier() {
        XCTAssertEqual(ConnectorStyle.from(rawString: "bezier"), .bezier)
    }

    func testParsePolyline() {
        XCTAssertEqual(ConnectorStyle.from(rawString: "polyline"), .polyline)
    }

    func testNilFallsBackToBezier() {
        // Pre-feature behaviour was always bezier; absent pref must keep that.
        XCTAssertEqual(ConnectorStyle.from(rawString: nil), .bezier)
    }

    func testUnknownValueFallsBackToBezier() {
        XCTAssertEqual(ConnectorStyle.from(rawString: "spaghetti"), .bezier)
        XCTAssertEqual(ConnectorStyle.from(rawString: ""), .bezier)
    }

    func testEveryCaseIsCovered() {
        // Sanity check that the picker UI exhaustively covers the enum.
        XCTAssertEqual(ConnectorStyle.allCases.count, 2)
    }
}
