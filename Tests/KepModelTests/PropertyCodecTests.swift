import XCTest
@testable import KepModel

/// Phase 1 of the Typed Node Properties keystone (#200): the pure
/// `PropertyValue` / `PropertyType` / `PropertyCodec` model. These tests are
/// fully headless and lock the codec's round-trip + canonical-form contract.
final class PropertyCodecTests: XCTestCase {

    /// decode(encode(v), as: v.kind) == v for representative values of each type.
    func testRoundTripPerType() {
        let cases: [PropertyValue] = [
            .text("hello world"),
            .text(""),                       // empty text is still a valid text value
            .text("a, b = c with `tick` inside"),
            .number(0),
            .number(3),
            .number(3.5),
            .number(-0.25),
            .number(1.0 / 3.0),              // irrational-ish: must round-trip exactly
            .number(1e20),
            .number(-1e-9),
            .checkbox(true),
            .checkbox(false),
            .list([]),
            .list(["alpha"]),
            .list(["alpha", "beta", "gamma"]),
            .list(["has,comma", "has\"quote", "has=eq"]),
            .topicRef(uid: "abc123"),
            .date(dateUTC(2026, 6, 20)),                       // date-only
            .date(dateUTC(2026, 6, 20, 14, 30, 0)),            // instant
        ]
        for v in cases {
            let encoded = PropertyCodec.encode(v)
            let decoded = PropertyCodec.decode(encoded, as: v.kind)
            XCTAssertEqual(decoded, v, "round-trip failed for \(v) (encoded=\(encoded))")
        }
    }

    /// Canonical encodings are exactly what the design specifies — these strings
    /// are what lands in the `.mmd` file, so pin them.
    func testCanonicalEncodings() {
        XCTAssertEqual(PropertyCodec.encode(.number(3)), "3")          // no trailing .0
        XCTAssertEqual(PropertyCodec.encode(.number(3.5)), "3.5")
        XCTAssertEqual(PropertyCodec.encode(.number(-0.25)), "-0.25")
        XCTAssertEqual(PropertyCodec.encode(.checkbox(true)), "true")
        XCTAssertEqual(PropertyCodec.encode(.checkbox(false)), "false")
        XCTAssertEqual(PropertyCodec.encode(.list(["a", "b"])), #"["a","b"]"#)
        XCTAssertEqual(PropertyCodec.encode(.list([])), "[]")
        XCTAssertEqual(PropertyCodec.encode(.topicRef(uid: "u1")), "u1")
        XCTAssertEqual(PropertyCodec.encode(.date(dateUTC(2026, 6, 20))), "2026-06-20")
        XCTAssertEqual(PropertyCodec.encode(.date(dateUTC(2026, 6, 20, 14, 30, 0))), "2026-06-20T14:30:00Z")
    }

    /// No encoded value contains a newline or ends in a backtick — the two
    /// substrate hazards from #211 the typed layer must avoid.
    func testEncodingsAreSubstrateSafe() {
        let values: [PropertyValue] = [
            .number(3.5), .checkbox(true), .list(["a`", "b"]),
            .topicRef(uid: "u"), .date(dateUTC(2026, 1, 1, 1, 2, 3)),
        ]
        for v in values {
            let s = PropertyCodec.encode(v)
            XCTAssertFalse(s.contains("\n"), "\(v) encoded with a newline")
            XCTAssertFalse(s.hasSuffix("`"), "\(v) encoded ending in a backtick")
        }
    }

    /// Strict types reject malformed strings (so the caller falls back to text);
    /// text/topicRef are total.
    func testDecodeRejectsMalformed() {
        XCTAssertNil(PropertyCodec.decode("notanumber", as: .number))
        XCTAssertNil(PropertyCodec.decode("", as: .number))
        XCTAssertNil(PropertyCodec.decode("inf", as: .number))
        XCTAssertNil(PropertyCodec.decode("nan", as: .number))
        XCTAssertNil(PropertyCodec.decode("yes", as: .checkbox))
        XCTAssertNil(PropertyCodec.decode("TRUE", as: .checkbox))       // case-strict
        XCTAssertNil(PropertyCodec.decode("not-a-date", as: .date))
        XCTAssertNil(PropertyCodec.decode("2026/06/20", as: .date))
        XCTAssertNil(PropertyCodec.decode("not json", as: .list))
        XCTAssertNil(PropertyCodec.decode("[1,2,3]", as: .list))        // non-string elements
        XCTAssertNil(PropertyCodec.decode(#"{"a":1}"#, as: .list))      // object, not array
        XCTAssertNil(PropertyCodec.decode("", as: .topicRef))

        // Text accepts anything; topicRef accepts any non-empty string.
        XCTAssertEqual(PropertyCodec.decode("anything", as: .text), .text("anything"))
        XCTAssertEqual(PropertyCodec.decode("u1", as: .topicRef), .topicRef(uid: "u1"))
    }

    func testKindMatchesCase() {
        XCTAssertEqual(PropertyValue.text("x").kind, .text)
        XCTAssertEqual(PropertyValue.number(1).kind, .number)
        XCTAssertEqual(PropertyValue.date(.init()).kind, .date)
        XCTAssertEqual(PropertyValue.checkbox(true).kind, .checkbox)
        XCTAssertEqual(PropertyValue.list([]).kind, .list)
        XCTAssertEqual(PropertyValue.topicRef(uid: "u").kind, .topicRef)
    }

    // MARK: - Helpers

    private func dateUTC(_ y: Int, _ mo: Int, _ d: Int,
                         _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: mo, day: d,
                                             hour: h, minute: mi, second: s))!
    }
}
