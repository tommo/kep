import XCTest
import MindoPlantUML

final class PlantUMLRendererTests: XCTestCase {

    /// `locate()` should consistently return either a tool or nil — and the
    /// `isAvailable` flag should agree.
    func testLocateAndAvailableAgree() {
        let r = PlantUMLRenderer()
        XCTAssertEqual(r.isAvailable, r.locate() != nil)
    }

    /// `installHint` should mention Homebrew + the local app-support fallback.
    func testInstallHintGivesActionableInstructions() {
        let hint = PlantUMLRenderer().installHint
        XCTAssertTrue(hint.contains("brew install"))
        XCTAssertTrue(hint.contains("plantuml.jar"))
    }

    /// When PlantUML is not installed, `renderSVG` should throw `.toolMissing`
    /// for diagrams that still need the Java path, not crash. Uses a class
    /// diagram so it bypasses the native sequence renderer. (Skip when the host
    /// happens to have PlantUML — we still get confidence from locate above.)
    func testRenderThrowsToolMissingWhenAbsent() throws {
        let r = PlantUMLRenderer()
        try XCTSkipIf(r.isAvailable, "PlantUML is available; skipping toolMissing assertion")
        XCTAssertThrowsError(try r.renderSVG(source: "@startuml\nclass Foo\nclass Bar\nFoo --|> Bar\n@enduml")) { error in
            guard case PlantUMLRenderer.RenderError.toolMissing = error else {
                XCTFail("Expected .toolMissing, got \(error)")
                return
            }
        }
    }

    /// Sequence diagrams render natively with no external tool — even when
    /// PlantUML is absent. Regression guard for the native-first wiring.
    func testSequenceRendersNativelyWithoutTool() throws {
        let data = try PlantUMLRenderer().renderSVG(source: "@startuml\nAlice -> Bob: hi\n@enduml")
        let svg = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(svg.hasPrefix("<?xml") || svg.contains("<svg"))
        XCTAssertTrue(svg.contains("Alice"))
    }
}
