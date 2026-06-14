import XCTest
@testable import MindoCore

final class SidebarExpansionStateTests: XCTestCase {

    func testRoundTrip() {
        let map = ["/ws/a": true, "/ws/b": false]
        let encoded = SidebarExpansionState.encode(map)
        XCTAssertEqual(SidebarExpansionState.decode(encoded), map)
    }

    func testEmptyMapEncodesToEmptyString() {
        XCTAssertEqual(SidebarExpansionState.encode([:]), "")
    }

    func testDecodeNilOrGarbageYieldsEmpty() {
        XCTAssertTrue(SidebarExpansionState.decode(nil).isEmpty)
        XCTAssertTrue(SidebarExpansionState.decode("").isEmpty)
        XCTAssertTrue(SidebarExpansionState.decode("not json").isEmpty)
        XCTAssertTrue(SidebarExpansionState.decode("[1,2,3]").isEmpty)   // wrong shape
    }

    func testIsExpandedUsesMapThenDefault() {
        let map = ["/ws/open": true, "/ws/closed": false]
        XCTAssertTrue(SidebarExpansionState.isExpanded("/ws/open", in: map, defaultExpanded: false))
        XCTAssertFalse(SidebarExpansionState.isExpanded("/ws/closed", in: map, defaultExpanded: true))
        // Untouched paths take the default.
        XCTAssertTrue(SidebarExpansionState.isExpanded("/ws/new", in: map, defaultExpanded: true))
        XCTAssertFalse(SidebarExpansionState.isExpanded("/ws/new", in: map, defaultExpanded: false))
    }

    func testEncodeIsStableForSameMap() {
        let map = ["/z": true, "/a": false, "/m": true]
        XCTAssertEqual(SidebarExpansionState.encode(map), SidebarExpansionState.encode(map))
    }
}
