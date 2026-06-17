import XCTest
import Foundation
import MindoPlantUML

final class PlantUMLCatalogTests: XCTestCase {

    func testKeywordRegexPatternMatchesCatalogVocabulary() throws {
        let re = try NSRegularExpression(pattern: PlantUMLCatalog.keywordRegexPattern)
        func matches(_ s: String) -> Bool {
            re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
        for kw in ["participant", "skinparam", "state", "@startmindmap", "!define", "%date"] {
            XCTAssertTrue(matches(kw), "should highlight \(kw)")
        }
        XCTAssertTrue(matches("ACTOR"), "case-insensitive")
        XCTAssertFalse(matches("participantx"), "whole-token only")
        XCTAssertFalse(matches("frobnicate"))
        XCTAssertTrue(matches("!ifdef"), "if must not shadow ifdef")
    }

    func testKeywordsAreCuratedSingleTokens() {
        let kws = PlantUMLCatalog.keywords
        XCTAssertGreaterThan(kws.count, 100)
        // No whitespace, no HTML entities, no bare symbols.
        for k in kws {
            XCTAssertFalse(k.contains(" "), "no multi-word keyword: \(k)")
            XCTAssertFalse(k.contains("&"), "no HTML entity: \(k)")
            XCTAssertFalse(k.contains("<") || k.contains("["), "no symbol token: \(k)")
        }
        XCTAssertTrue(kws.contains("participant"))
        XCTAssertTrue(kws.contains("skinparam"))
        XCTAssertTrue(kws.contains("@startuml"))
        XCTAssertTrue(kws.contains("!define"))
    }

    func testSnippetsAreHtmlUnescaped() {
        let bodies = PlantUMLCatalog.snippets.map(\.body).joined(separator: "\n")
        XCTAssertFalse(bodies.contains("&gt;"))
        XCTAssertFalse(bodies.contains("&lt;"))
        XCTAssertTrue(bodies.contains("->"), "arrows decoded")
        XCTAssertTrue(bodies.contains("<|--"), "class inheritance decoded")
        // Every snippet has a non-empty body and the common ones a @start.
        XCTAssertEqual(PlantUMLCatalog.snippets.count, 15)
        XCTAssertTrue(PlantUMLCatalog.snippets.allSatisfy { !$0.body.isEmpty })
        XCTAssertTrue(PlantUMLCatalog.snippets.first { $0.title == "Sequence" }!.body.hasPrefix("@startuml"))
    }

    func testHtmlUnescapeDoublyEscaped() {
        XCTAssertEqual(PlantUMLCatalog.htmlUnescape("a -&gt; b"), "a -> b")
        XCTAssertEqual(PlantUMLCatalog.htmlUnescape("&lt;&lt;include&gt;&gt;"), "<<include>>")
    }

    // MARK: - Completion

    func testCompletionPrefixMatch() {
        let c = PlantUMLCompletion.completions(forPartialWord: "part")
        XCTAssertTrue(c.contains("participant"))
        XCTAssertTrue(c.contains("partition"))
        XCTAssertFalse(c.contains("actor"))
    }

    func testCompletionMatchesBareWordAfterPunctuation() {
        // NSTextView strips the leading '@', so "startuml" should still surface @startuml.
        let c = PlantUMLCompletion.completions(forPartialWord: "startu")
        XCTAssertTrue(c.contains("@startuml"))
    }

    func testCompletionSkinparamContext() {
        let c = PlantUMLCompletion.completions(forPartialWord: "back", lineUpToCaret: "skinparam back")
        XCTAssertTrue(c.contains("backgroundColor"))
    }

    func testCompletionEmptyAndExactDropped() {
        XCTAssertTrue(PlantUMLCompletion.completions(forPartialWord: "").isEmpty)
        XCTAssertFalse(PlantUMLCompletion.completions(forPartialWord: "actor").contains("actor"))
    }
}
