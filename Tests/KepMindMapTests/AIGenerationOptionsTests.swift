import XCTest
@testable import KepGenAI

final class AIGenerationOptionsTests: XCTestCase {

    func testTemperaturePresetValuesAscend() {
        let values = AITemperature.allCases.map(\.value)
        XCTAssertEqual(values, values.sorted(), "presets should be ordered low→high")
        XCTAssertEqual(AITemperature.deterministic.value, 0.01, accuracy: 0.0001)
        XCTAssertEqual(AITemperature.creative.value, 1.0, accuracy: 0.0001)
        XCTAssertEqual(AITemperature.default, .balanced)
    }

    func testAutoLanguageLeavesPromptUntouched() {
        let p = "Summarize this."
        XCTAssertEqual(AIOutputLanguage.auto.applied(to: p), p)
        XCTAssertTrue(AIOutputLanguage.auto.isAuto)
    }

    func testNonAutoLanguageAppendsDirective() {
        let lang = AIOutputLanguage.by(id: "ja")
        XCTAssertEqual(lang.name, "Japanese")
        let out = lang.applied(to: "Hello")
        XCTAssertTrue(out.hasPrefix("Hello"))
        XCTAssertTrue(out.contains("Respond in Japanese."))
    }

    func testLookupUnknownLanguageFallsBackToAuto() {
        XCTAssertTrue(AIOutputLanguage.by(id: "klingon").isAuto)
    }

    func testLanguageListStartsWithAutoAndHasUniqueIds() {
        XCTAssertEqual(AIOutputLanguage.all.first?.id, "")
        let ids = AIOutputLanguage.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
