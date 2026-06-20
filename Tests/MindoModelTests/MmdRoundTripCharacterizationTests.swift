import XCTest
@testable import MindoModel

/// Phase 0 of the Typed Node Properties keystone (#200): lock the `.mmd`
/// serialization substrate BEFORE a typed property layer is added on top, so
/// any drift the typed layer introduces is caught by a pre-existing green gate.
///
/// CHARACTERIZED FINDING — byte-identity does NOT hold today: a real source
/// file re-serializes 198 bytes shorter than the original because note `<pre>`
/// bodies decode HTML entities on read (`&quot;` → `"`) and re-emit the literal
/// character. That drift is semantically lossless and lives in the note codec,
/// NOT the `> ` attribute block the typed-property layer will touch. So the
/// enforced back-compat invariants here are IDEMPOTENCY (write∘parse is a fix
/// point) and SEMANTIC round-trip (text + attributes + extras preserved). The
/// typed layer must keep both green; see [[card #200]].
final class MmdRoundTripCharacterizationTests: XCTestCase {

    private func fx(_ name: String) throws -> URL {
        guard let u = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name.replacingOccurrences(of: ".mmd", with: ""),
                                 withExtension: "mmd", subdirectory: "Fixtures")
        else { throw XCTSkip("fixture \(name) not found") }
        return u
    }

    /// Collect every (path, attributes) pair in document order so two maps can
    /// be compared attribute-for-attribute.
    private func attributeSnapshot(_ map: MindMap) -> [[String: String]] {
        var out: [[String: String]] = []
        map.root?.traverse { out.append($0.attributes) }
        return out
    }

    private func textSnapshot(_ map: MindMap) -> [String] {
        var out: [String] = []
        map.root?.traverse { out.append($0.text) }
        return out
    }

    // MARK: - Real-world fixture

    /// The regression gate the existing suite under-tests: writing is a fix
    /// point. parse→write→parse→write must produce identical bytes on the
    /// second pass (any non-idempotent serialization is a bug the typed layer
    /// could amplify).
    func testDemoFixtureIdempotentUnderReparse() throws {
        let src = try String(contentsOf: try fx("DemoMindMap.mmd"), encoding: .utf8)
        let write1 = try MindMap(text: src).write()
        let write2 = try MindMap(text: write1).write()
        XCTAssertEqual(write1, write2, "write∘parse must be a fix point (idempotent)")
    }

    /// Semantic round-trip on the real file: every topic's text and full
    /// attribute dict survive a parse→write→parse cycle unchanged.
    func testDemoFixtureSemanticRoundTrip() throws {
        let src = try String(contentsOf: try fx("DemoMindMap.mmd"), encoding: .utf8)
        let first = try MindMap(text: src)
        let second = try MindMap(text: first.write())
        XCTAssertEqual(textSnapshot(first), textSnapshot(second), "topic text must survive round-trip")
        XCTAssertEqual(attributeSnapshot(first), attributeSnapshot(second), "every attribute must survive round-trip")
    }

    // MARK: - Attribute block (the substrate the typed layer edits)

    /// The attribute values a typed encoder actually emits (canonical numbers,
    /// ISO dates, true/false, JSON-array lists, single-line text) plus the
    /// stresses they must survive (commas, `=`, internal backticks, unicode).
    /// All on one topic — assert the combination is idempotent and every value
    /// round-trips verbatim. This is the green back-compat gate the typed layer
    /// must keep passing.
    func testSafeAttributeValuesRoundTrip() throws {
        let safe: [String: String] = [
            "plain":        "hello world",
            "withComma":    "a,b,c",
            "withEquals":   "k=v=w",
            "withBacktick": "inline `code` here",
            "jsonList":     #"["alpha","beta","gamma"]"#,
            "number":       "3.5",
            "negative":     "-0.25",
            "iso8601":      "2026-06-20",
            "instant":      "2026-06-20T14:30:00Z",
            "bool":         "true",
            "unicode":      "café — naïve — 日本語",
        ]
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let node = root.addChild(text: "Node")
        for (k, v) in safe { node.setAttribute(k, v) }

        let write1 = map.write()
        let reparsed = try MindMap(text: write1)
        XCTAssertEqual(reparsed.write(), write1, "attribute serialization must be idempotent")

        let target = reparsed.root?.children.first
        for (k, v) in safe {
            XCTAssertEqual(target?.attribute(k), v, "attribute \(k) must round-trip its value verbatim")
        }
    }

    /// CHARACTERIZED SUBSTRATE GAPS (found by this Phase 0 suite): the `> ` line
    /// uses a backtick-fence value encoding (``key=`value` ``) whose parser
    /// regex `(\`+)(.*?)\2` mishandles three value shapes — a value containing a
    /// newline (splits the line), a value ENDING in a backtick, and a lone
    /// backtick. Each fails to round-trip today. They are wrapped as EXPECTED
    /// failures so this suite stays green while tracking the bug: when the
    /// serializer is fixed these flip to unexpected passes and flag the win.
    /// Constraint for the typed layer until then: text property values must be
    /// single-line and must not end in a backtick (lists use JSON, which is
    /// safe). See [[card]] for the fix. The fix belongs to the writer/parser,
    /// not the typed layer.
    func testKnownAttributeSerializationGaps() throws {
        let broken: [String: String] = [
            "withNewline":   "line one\nline two",   // newline splits the `> ` line
            "trailBacktick": "ends in tick`",         // greedy fence swallows the closer
            "onlyBacktick":  "`",                      // lone backtick
        ]
        for (k, v) in broken {
            XCTExpectFailure("attribute value '\(k)' is a known serialization gap (#211)") {
                let map = MindMap()
                let root = Topic(text: "Root"); map.root = root
                root.setAttribute(k, v)
                let reparsed = try! MindMap(text: map.write())
                XCTAssertEqual(reparsed.root?.attribute(k), v)
            }
        }
    }

    /// Every reserved renderer/importer key the writer knows about must survive
    /// a round-trip — these are the keys the typed inference layer must NOT
    /// reinterpret destructively.
    func testReservedKeysRoundTrip() throws {
        let reserved: [String: String] = [
            TopicAttribute.fillColor: "#FF8800",
            TopicAttribute.textColor: "#101010",
            TopicAttribute.borderColor: "#000000",
            TopicAttribute.leftSide: "true",
            TopicAttribute.collapsed: "false",
            TopicAttribute.emoticon: "rocket",
            TopicAttribute.edgeColor: "#123456",
            TopicAttribute.edgeStyle: "bezier",
            TopicAttribute.edgeWidth: "2",
            TopicAttribute.textAlign: "center",
            TopicAttribute.offsetX: "12.5",
            TopicAttribute.offsetY: "-8",
        ]
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        for (k, v) in reserved { root.setAttribute(k, v) }

        let reparsed = try MindMap(text: map.write())
        for (k, v) in reserved {
            XCTAssertEqual(reparsed.root?.attribute(k), v, "reserved key \(k) must round-trip")
        }
    }

    /// Unknown/foreign keys must be preserved untouched — this is the mechanism
    /// the deferred `__types__` sidecar (and any future metadata) relies on.
    func testUnknownKeysPreserved() throws {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        root.setAttribute("customX", "y")
        root.setAttribute("__types__", #"{"priority":"number"}"#)
        root.setAttribute("vendor.future.flag", "on")

        let reparsed = try MindMap(text: map.write())
        XCTAssertEqual(reparsed.root?.attribute("customX"), "y")
        XCTAssertEqual(reparsed.root?.attribute("__types__"), #"{"priority":"number"}"#)
        XCTAssertEqual(reparsed.root?.attribute("vendor.future.flag"), "on")
    }

    /// The attribute serializer's ordering contract: keys are emitted sorted, so
    /// the same dict always serializes to the same string regardless of insert
    /// order. The typed layer must not disturb this (it keys cache/diff stability).
    func testAttributeOrderingIsSortedAndStable() throws {
        let a = ["zebra": "1", "alpha": "2", "mango": "3"]
        let b = ["mango": "3", "zebra": "1", "alpha": "2"]   // same dict, different literal order
        XCTAssertEqual(MindMap.attributesAsString(a), MindMap.attributesAsString(b))
        // Sorted: alpha, mango, zebra.
        XCTAssertEqual(MindMap.attributesAsString(a), "alpha=`2`,mango=`3`,zebra=`1`")
    }
}
