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

    /// When PlantUML is not installed, `renderSVG` should throw `.toolMissing`,
    /// not crash. (Skip when the host happens to have PlantUML — we still get
    /// confidence from the locate test above.)
    func testRenderThrowsToolMissingWhenAbsent() throws {
        let r = PlantUMLRenderer()
        try XCTSkipIf(r.isAvailable, "PlantUML is available; skipping toolMissing assertion")
        XCTAssertThrowsError(try r.renderSVG(source: "@startuml\nA -> B\n@enduml")) { error in
            guard case PlantUMLRenderer.RenderError.toolMissing = error else {
                XCTFail("Expected .toolMissing, got \(error)")
                return
            }
        }
    }
}
