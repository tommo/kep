import XCTest
@testable import MindoPlantUML

final class PlantUMLTemplatesTests: XCTestCase {

    func testCatalogIsNonEmptyAndBlankIsFirst() {
        XCTAssertGreaterThanOrEqual(PlantUMLTemplates.all.count, 19)
        XCTAssertEqual(PlantUMLTemplates.all.first?.id, "blank")
        XCTAssertEqual(PlantUMLTemplates.blank.id, "blank")
    }

    func testIdsAndNamesAreUnique() {
        let ids = PlantUMLTemplates.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "template ids must be unique")
        let names = PlantUMLTemplates.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "template display names must be unique")
    }

    func testEveryBodyIsAFencedDiagram() {
        for t in PlantUMLTemplates.all {
            let body = t.body.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(body.hasPrefix("@start"), "\(t.id) must open with an @start fence")
            XCTAssertTrue(body.contains("@end"), "\(t.id) must contain an @end fence")
            // The opening and closing fences must agree on the diagram kind
            // (@startuml/@enduml, @startgantt/@endgantt, …).
            let kind = body
                .prefix(while: { $0 != "\n" })
                .dropFirst("@start".count)
            XCTAssertTrue(body.contains("@end\(kind)"), "\(t.id) open/close fences must match (@end\(kind))")
        }
    }

    func testLookupById() {
        XCTAssertEqual(PlantUMLTemplates.template(id: "sequence")?.name, "Sequence")
        XCTAssertNil(PlantUMLTemplates.template(id: "does-not-exist"))
    }

    func testGroupedCoversEveryTemplateOnce() {
        let flattened = PlantUMLTemplates.grouped.flatMap(\.templates)
        XCTAssertEqual(flattened.count, PlantUMLTemplates.all.count)
        XCTAssertEqual(Set(flattened.map(\.id)), Set(PlantUMLTemplates.all.map(\.id)))
        // Categories appear once each, in first-seen order.
        let cats = PlantUMLTemplates.grouped.map(\.category)
        XCTAssertEqual(Set(cats).count, cats.count)
    }
}
