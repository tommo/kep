import XCTest
@testable import KepModel

/// Phase 2 of the Typed Node Properties keystone (#200): the typed-property
/// projection over `Topic.attributes`, plus the back-compat guarantee that
/// properties round-trip losslessly through the existing `.mmd` `> ` serializer.
final class TopicPropertiesTests: XCTestCase {

    // MARK: - Inference

    func testInferencePicksMostSpecificType() {
        XCTAssertEqual(PropertyInference.infer("true"), .checkbox(true))
        XCTAssertEqual(PropertyInference.infer("false"), .checkbox(false))
        XCTAssertEqual(PropertyInference.infer("42"), .number(42))
        XCTAssertEqual(PropertyInference.infer("3.5"), .number(3.5))
        XCTAssertEqual(PropertyInference.infer("2026-06-21"),
                       .date(PropertyCodec.decode("2026-06-21", as: .date).flatMap { if case .date(let d) = $0 { return d } else { return nil } }!))
        XCTAssertEqual(PropertyInference.infer(#"["a","b"]"#), .list(["a", "b"]))
    }

    func testInferenceFallsBackToText() {
        XCTAssertEqual(PropertyInference.infer("hello world"), .text("hello world"))
        XCTAssertEqual(PropertyInference.infer(""), .text(""))
        // A bare word that isn't a bool/number/date/json stays text.
        XCTAssertEqual(PropertyInference.infer("active"), .text("active"))
    }

    // MARK: - Projection over attributes

    func testSetGetUserProperty() {
        let t = Topic(text: "n")
        t.setProperty("status", .text("active"))
        t.setProperty("priority", .number(3))
        XCTAssertEqual(t.property("status"), .text("active"))
        XCTAssertEqual(t.property("priority"), .number(3))
        XCTAssertEqual(Set(t.propertyKeys), ["priority", "status"])
    }

    func testReservedKeysAreNotProperties() {
        let t = Topic(text: "n")
        t.setAttribute(TopicAttribute.fillColor, "#fff")
        t.setAttribute(ExtraTopic.topicUidAttr, "uid-1")
        t.setAttribute("mmd.custom", "x")
        t.setAttribute("extras.note.encrypted", "true")
        XCTAssertTrue(t.propertyKeys.isEmpty, "built-in/extra/namespaced attrs are not user properties")
        XCTAssertNil(t.property(TopicAttribute.fillColor))
        // setProperty must refuse to shadow a reserved key.
        t.setProperty(TopicAttribute.fillColor, .text("oops"))
        XCTAssertEqual(t.attribute(TopicAttribute.fillColor), "#fff")
    }

    func testSetNilRemovesProperty() {
        let t = Topic(text: "n")
        t.setProperty("status", .text("active"))
        t.setProperty("status", nil)
        XCTAssertNil(t.property("status"))
        XCTAssertNil(t.attribute("status"))
    }

    // MARK: - Back-compat: round-trip through .mmd

    func testPropertiesRoundTripThroughMmdSerializer() throws {
        let root = Topic(text: "Root")
        let map = MindMap(root: root)
        let due = try XCTUnwrap(PropertyCodec.decode("2026-06-21", as: .date))
        root.setProperty("status", .text("active"))
        root.setProperty("priority", .number(3))
        root.setProperty("done", .checkbox(true))
        root.setProperty("due", due)
        root.setProperty("tags", .list(["urgent", "review"]))

        let serialized = map.write()
        let reparsed = try MindMap(text: serialized)
        let r2 = try XCTUnwrap(reparsed.root)

        XCTAssertEqual(r2.property("status"), .text("active"))
        XCTAssertEqual(r2.property("priority"), .number(3))
        XCTAssertEqual(r2.property("done"), .checkbox(true))
        XCTAssertEqual(r2.property("due"), due)
        XCTAssertEqual(r2.property("tags"), .list(["urgent", "review"]))
        XCTAssertEqual(Set(r2.propertyKeys), ["done", "due", "priority", "status", "tags"])
    }
}
