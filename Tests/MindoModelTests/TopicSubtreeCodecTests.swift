import XCTest
@testable import MindoModel

final class TopicSubtreeCodecTests: XCTestCase {

    func testRoundTripsTextOnly() throws {
        let t = Topic(text: "Solo")
        let data = try TopicSubtreeCodec.encode(t)
        let restored = try TopicSubtreeCodec.decode(data)
        XCTAssertEqual(restored.text, "Solo")
        XCTAssertTrue(restored.children.isEmpty)
    }

    func testRoundTripsAttributes() throws {
        let t = Topic(text: "T")
        t.setAttribute(TopicAttribute.fillColor, "#FF0000")
        t.setAttribute(TopicAttribute.collapsed, "true")
        let data = try TopicSubtreeCodec.encode(t)
        let restored = try TopicSubtreeCodec.decode(data)
        XCTAssertEqual(restored.attribute(TopicAttribute.fillColor), "#FF0000")
        XCTAssertEqual(restored.attribute(TopicAttribute.collapsed), "true")
    }

    func testRoundTripsExtras() throws {
        let t = Topic(text: "T")
        t.setExtra(ExtraLink(uri: "https://example.com"))
        t.setExtra(ExtraNote(text: "hello"))
        let data = try TopicSubtreeCodec.encode(t)
        let restored = try TopicSubtreeCodec.decode(data)
        XCTAssertEqual((restored.extra(.link) as? ExtraLink)?.uri, "https://example.com")
        XCTAssertEqual((restored.extra(.note) as? ExtraNote)?.text, "hello")
    }

    func testRoundTripsSnippets() throws {
        let t = Topic(text: "T")
        t.putCodeSnippet(language: "swift", body: "let x = 1\n")
        let data = try TopicSubtreeCodec.encode(t)
        let restored = try TopicSubtreeCodec.decode(data)
        XCTAssertEqual(restored.codeSnippets["swift"], "let x = 1\n")
    }

    func testRoundTripsDeepSubtree() throws {
        let root = Topic(text: "Root")
        let a = root.addChild(text: "A")
        _ = a.addChild(text: "A1")
        _ = root.addChild(text: "B")
        let data = try TopicSubtreeCodec.encode(root)
        let restored = try TopicSubtreeCodec.decode(data)
        XCTAssertEqual(restored.text, "Root")
        XCTAssertEqual(restored.children.map(\.text), ["A", "B"])
        XCTAssertEqual(restored.children[0].children.map(\.text), ["A1"])
    }

    func testRestoredTopicHasNoParent() throws {
        // Caller is expected to attach via parent.append; the deserialized
        // root must arrive detached so it can land anywhere.
        let t = Topic(text: "Solo")
        let data = try TopicSubtreeCodec.encode(t)
        let restored = try TopicSubtreeCodec.decode(data)
        XCTAssertNil(restored.parent)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try TopicSubtreeCodec.decode(Data("not json".utf8)))
    }

    func testWrongVersionThrows() {
        let bytes = #"{"v": 999, "topic": {"text": "x"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try TopicSubtreeCodec.decode(bytes)) { error in
            guard case TopicSubtreeCodec.CodecError.wrongVersion = error else {
                XCTFail("expected .wrongVersion, got \(error)")
                return
            }
        }
    }

    func testMissingTopicEnvelopeThrows() {
        let bytes = #"{"v": 1}"#.data(using: .utf8)!
        XCTAssertThrowsError(try TopicSubtreeCodec.decode(bytes)) { error in
            guard case TopicSubtreeCodec.CodecError.missingTopic = error else {
                XCTFail("expected .missingTopic, got \(error)")
                return
            }
        }
    }
}
