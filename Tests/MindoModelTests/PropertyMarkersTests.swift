import XCTest
@testable import MindoModel

/// Phase 5 of the keystone (#200): the pure marker-row logic that the canvas
/// renders from well-known properties.
final class PropertyMarkersTests: XCTestCase {

    func testNoMarkersWhenNoWellKnownProperties() {
        let t = Topic(text: "n")
        t.setProperty("status", .text("active"))   // not a well-known key
        XCTAssertTrue(PropertyMarkers.markerRow(for: t).isEmpty)
    }

    func testPriorityDoneTagsInStableOrder() {
        let t = Topic(text: "n")
        t.setProperty(PropertyMarkers.tagsKey, .list(["a", "b"]))
        t.setProperty(PropertyMarkers.doneKey, .checkbox(true))
        t.setProperty(PropertyMarkers.priorityKey, .number(2))
        let roles = PropertyMarkers.markerRow(for: t).map(\.role)
        XCTAssertEqual(roles, [.priority(2), .doneTrue, .tags(2)])
    }

    func testDoneFalseRendersHollowMarker() {
        let t = Topic(text: "n")
        t.setProperty(PropertyMarkers.doneKey, .checkbox(false))
        let markers = PropertyMarkers.markerRow(for: t)
        XCTAssertEqual(markers.map(\.role), [.doneFalse])
        XCTAssertEqual(markers.first?.symbolName, "circle")
    }

    func testPriorityClampedToOneThroughFive() {
        XCTAssertEqual(PropertyMarkers.clampPriority(0), 1)
        XCTAssertEqual(PropertyMarkers.clampPriority(-3), 1)
        XCTAssertEqual(PropertyMarkers.clampPriority(2.6), 3)
        XCTAssertEqual(PropertyMarkers.clampPriority(99), 5)
    }

    func testWrongTypeProducesNoMarker() {
        let t = Topic(text: "n")
        // priority stored as text (not a number) → no marker.
        t.setProperty(PropertyMarkers.priorityKey, .text("high"))
        // tags stored empty → no marker.
        t.setProperty(PropertyMarkers.tagsKey, .list([]))
        XCTAssertTrue(PropertyMarkers.markerRow(for: t).isEmpty)
    }

    func testSymbolNames() {
        XCTAssertEqual(PropertyMarker(role: .priority(1)).symbolName, "flag.fill")
        XCTAssertEqual(PropertyMarker(role: .doneTrue).symbolName, "checkmark.circle.fill")
        XCTAssertEqual(PropertyMarker(role: .tags(3)).symbolName, "tag.fill")
    }
}
