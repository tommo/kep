import XCTest
@testable import MindoModel

/// Importers parse untrusted external files, so malformed / adversarial
/// input must fail GRACEFULLY — throw, or return a (possibly minimal) map —
/// never crash (force-unwrap, index-out-of-range, infinite loop). Each case
/// just calls parse and tolerates either outcome; the value is that the test
/// process survives every input.
final class ImporterRobustnessTests: XCTestCase {

    private let garbage = [
        "", "   ", "\n\n\n", "\t",
        "not a real document at all",
        "<<<>>>", "{{{}}}", "][}{",
        "\u{0}\u{1}\u{2}",                       // control chars
        String(repeating: "a", count: 100_000), // very long single token
        "😀🎉".repeatedTimes(1000),
    ]

    private func tolerate(_ body: () throws -> MindMap) {
        // Either a thrown error or a returned map is acceptable — we only
        // require that we get here without crashing.
        do { _ = try body() } catch { /* graceful failure is fine */ }
    }

    // MARK: - FreeMind (XML)

    func testFreemindToleratesGarbage() {
        for s in garbage { tolerate { try FreemindImporter.parse(s) } }
    }

    func testFreemindToleratesMalformedXML() {
        let cases = [
            "<map>",                                   // unclosed
            "<map><node TEXT=\"a\"></map>",            // mismatched
            "<map><node></node></map>",                // node without TEXT
            "<?xml version=\"1.0\"?>",                  // declaration only
            "<map version=\"1.0\"><node TEXT=\"&badentity;\"/></map>", // bad entity
            "<map><node TEXT=\"a\"><node TEXT=\"b\"/></node>",          // unclosed root
        ]
        for s in cases { tolerate { try FreemindImporter.parse(s) } }
    }

    func testFreemindDeepNestingDoesNotCrash() {
        // 400 levels of nesting — recursive XML walk must not blow the stack
        // for a plausibly-deep map.
        let open = String(repeating: "<node TEXT=\"x\">", count: 400)
        let close = String(repeating: "</node>", count: 400)
        tolerate { try FreemindImporter.parse("<map version=\"1.0\">\(open)\(close)</map>") }
    }

    // MARK: - Mindmup (JSON)

    func testMindmupToleratesGarbage() {
        for s in garbage { tolerate { try MindmupImporter.parse(s) } }
    }

    func testMindmupToleratesMalformedJSON() {
        let cases = [
            "{}", "[]", "null", "true", "42", "\"string\"",
            "{\"id\":1}",                                  // missing title/ideas
            "{\"title\":\"x\",\"ideas\":\"notanobject\"}", // wrong type
            "{\"ideas\":{\"1\":{\"ideas\":{\"1\":{}}}}}",  // nested but empty
            "{\"title\":",                                 // truncated
        ]
        for s in cases { tolerate { try MindmupImporter.parse(s) } }
    }

    // MARK: - Coggle (XML/markdown-ish)

    func testCoggleToleratesGarbage() {
        for s in garbage { tolerate { try CoggleImporter.parse(s) } }
    }

    // MARK: - Text outline

    func testTextOutlineToleratesGarbage() {
        for s in garbage { tolerate { try TextOutlineImporter.parse(s) } }
    }

    func testTextOutlineToleratesWeirdIndentation() {
        let cases = [
            "\t\t\t\tdeep first",                       // starts deeply indented
            "a\n\t\t\tb\nc",                             // jumps indent levels
            "   \n  \n    \n",                           // only whitespace lines
            "- item\n  - sub\n    - subsub",            // dash bullets
            "mixed\ttabs and    spaces",
        ]
        for s in cases { tolerate { try TextOutlineImporter.parse(s) } }
    }

    // MARK: - Valid-minimal inputs still parse to something sensible

    func testMinimalValidFreemindParses() throws {
        let map = try FreemindImporter.parse("<map version=\"1.0\"><node TEXT=\"Hi\"/></map>")
        XCTAssertEqual(map.root?.text, "Hi")
    }

    func testSingleLineTextOutlineParses() throws {
        let map = try TextOutlineImporter.parse("Just one line")
        XCTAssertEqual(map.root?.text, "Just one line")
    }
}

private extension String {
    func repeatedTimes(_ n: Int) -> String { String(repeating: self, count: n) }
}
