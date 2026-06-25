import XCTest
@testable import KepModel

/// Phase 5 of the keystone (#200): the pure marker-row logic that the canvas
/// renders from well-known properties.
final class PropertyMarkersTests: XCTestCase {

    func testNoMarkersWhenNoWellKnownProperties() {
        let t = Topic(text: "n")
        t.setProperty("status", .text("active"))   // not a well-known key
        XCTAssertTrue(PropertyMarkers.markerRow(for: t).isEmpty)
    }

    func testPriorityDoneProgressTagsInStableOrder() {
        let t = Topic(text: "n")
        t.setProperty(PropertyMarkers.tagsKey, .list(["a", "b"]))
        t.setProperty(PropertyMarkers.doneKey, .checkbox(true))
        t.setProperty(PropertyMarkers.priorityKey, .number(2))
        t.setProperty(PropertyMarkers.progressKey, .number(0.5))
        let roles = PropertyMarkers.markerRow(for: t).map(\.role)
        XCTAssertEqual(roles, [.priority(2), .doneTrue, .progress(0.5), .tags(2)])
    }

    func testProgressNormalization() {
        XCTAssertEqual(PropertyMarkers.normalizeProgress(0.5), 0.5, accuracy: 0.001)   // fraction
        XCTAssertEqual(PropertyMarkers.normalizeProgress(70), 0.7, accuracy: 0.001)    // percent
        XCTAssertEqual(PropertyMarkers.normalizeProgress(1), 1, accuracy: 0.001)       // 100%
        XCTAssertEqual(PropertyMarkers.normalizeProgress(-3), 0, accuracy: 0.001)      // clamp low
        XCTAssertEqual(PropertyMarkers.normalizeProgress(250), 1, accuracy: 0.001)     // clamp high
    }

    func testProgressOnlyFromNumber() {
        let t = Topic(text: "n")
        t.setProperty(PropertyMarkers.progressKey, .text("half"))   // not a number → no marker
        XCTAssertTrue(PropertyMarkers.markerRow(for: t).isEmpty)
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
