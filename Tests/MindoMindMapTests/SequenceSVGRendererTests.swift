import XCTest
@testable import MindoPlantUML

final class SequenceSVGRendererTests: XCTestCase {

    private func svg(_ src: String, isDark: Bool = false) -> String {
        SequenceSVGRenderer.renderSequenceSVG(source: src, isDark: isDark) ?? ""
    }

    func testProducesWellFormedRoot() {
        let s = svg("@startuml\nAlice -> Bob: hi\n@enduml")
        XCTAssertTrue(s.contains("<svg"))
        XCTAssertTrue(s.contains("width=\""))
        XCTAssertTrue(s.contains("height=\""))
        XCTAssertTrue(s.contains("viewBox=\"0 0 "))
        XCTAssertTrue(s.hasSuffix("</svg>"))
    }

    func testEscapesText() {
        let s = svg("@startuml\nAlice -> Bob: a < b & c > d\n@enduml")
        XCTAssertTrue(s.contains("a &lt; b &amp; c &gt; d"))
        XCTAssertFalse(s.contains("a < b & c > d"))
    }

    func testDashedMessageHasDashArray() {
        let solid = svg("@startuml\nA -> B: x\n@enduml")
        let dashed = svg("@startuml\nA --> B: x\n@enduml")
        XCTAssertTrue(dashed.contains("stroke-dasharray"))
        // A solid message still has dashed lifelines, so just assert the dashed
        // variant carries at least one more dasharray occurrence than solid.
        XCTAssertGreaterThan(dashed.components(separatedBy: "stroke-dasharray").count,
                             solid.components(separatedBy: "stroke-dasharray").count)
    }

    func testDarkPaletteDiffersFromLight() {
        let light = svg("@startuml\nA -> B: x\n@enduml", isDark: false)
        let dark = svg("@startuml\nA -> B: x\n@enduml", isDark: true)
        XCTAssertTrue(light.contains(SVGTheme.light.background))
        XCTAssertTrue(dark.contains(SVGTheme.dark.background))
        XCTAssertNotEqual(light, dark)
    }

    func testNonSequenceReturnsNil() {
        let classDiagram = PlantUMLCatalog.snippets.first { $0.title == "Class" }!.body
        XCTAssertNil(SequenceSVGRenderer.renderSequenceSVG(source: classDiagram, isDark: false))
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(SequenceSVGRenderer.renderSequenceSVG(source: "@startuml\n@enduml", isDark: false))
    }

    func testCatalogSnippetRenders() {
        let body = PlantUMLCatalog.snippets.first { $0.title == "Sequence" }!.body
        let s = svg(body)
        XCTAssertTrue(s.contains("<svg"))
        XCTAssertTrue(s.contains("Alice"))
        XCTAssertTrue(s.contains("Bob"))
        // the alt group label
        XCTAssertTrue(s.contains("alt"))
    }

    func testArrowheadsEmitted() {
        // filled (->) → polygon; open (->>) → polyline; cross (->x); circle (->o)
        XCTAssertTrue(svg("@startuml\nA -> B: x\n@enduml").contains("<polygon"))
        XCTAssertTrue(svg("@startuml\nA ->> B: x\n@enduml").contains("<polyline"))
        XCTAssertTrue(svg("@startuml\nA ->o B: x\n@enduml").contains("<circle"))
    }
}
