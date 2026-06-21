import XCTest
@testable import MindoPlantUML

final class PlantUMLOutlineTests: XCTestCase {
    func testOneItemPerDiagramBlockWithTitles() {
        let src = """
        @startuml
        title First
        A -> B
        @enduml

        @startmindmap
        * root
        @endmindmap
        """
        let items = PlantUMLOutline.items(for: src)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "First")          // explicit title line
        XCTAssertEqual(items[1].title, "Mindmap 2")      // type + ordinal fallback
        XCTAssertTrue(items.allSatisfy { $0.depth == 0 })
    }

    func testTargetsAreAscendingByteOffsets() {
        let src = "@startuml\nA->B\n@enduml\n\n@startuml\nC->D\n@enduml\n"
        let items = PlantUMLOutline.items(for: src)
        XCTAssertEqual(items.count, 2)
        let first = Int(items[0].target)!
        let second = Int(items[1].target)!
        XCTAssertEqual(first, 0)                          // first block starts at offset 0
        XCTAssertGreaterThan(second, first)              // second block is later in the file
    }

    func testSingleImplicitDiagramStillProducesAnItem() {
        // No @start fence → PlantUMLPages returns one whole-file page.
        let items = PlantUMLOutline.items(for: "A -> B\nB -> C\n")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].target, "0")
    }
}
