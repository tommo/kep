import XCTest
@testable import KepPlantUML

final class PlantUMLPagesTests: XCTestCase {

    func testSingleBlock() {
        let pages = PlantUMLPages.split("@startuml\nA -> B\n@enduml")
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].firstLine, 0)
        XCTAssertEqual(pages[0].lastLine, 2)
        XCTAssertTrue(pages[0].text.hasPrefix("@startuml"))
    }

    func testNoFenceReturnsWholeSourceAsOnePage() {
        let pages = PlantUMLPages.split("just some text\nno fences")
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].title, "Diagram")
        XCTAssertEqual(pages[0].text, "just some text\nno fences")
    }

    func testMultipleBlocks() {
        let src = """
        @startuml
        title First
        A -> B
        @enduml

        @startgantt
        [Task] lasts 2 days
        @endgantt
        """
        let pages = PlantUMLPages.split(src)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].title, "First")           // from in-block title
        XCTAssertEqual(pages[1].title, "Gantt 2")         // type + ordinal fallback
        XCTAssertTrue(pages[0].text.contains("A -> B"))
        XCTAssertTrue(pages[1].text.hasPrefix("@startgantt"))
        XCTAssertFalse(pages[0].text.contains("@startgantt"))
    }

    func testPageIndexForLine() {
        let src = "@startuml\nA->B\n@enduml\n\n@startuml\nC->D\n@enduml"
        let pages = PlantUMLPages.split(src)
        XCTAssertEqual(PlantUMLPages.pageIndex(forLine: 1, in: pages), 0)   // inside block 1
        XCTAssertEqual(PlantUMLPages.pageIndex(forLine: 5, in: pages), 1)   // inside block 2
        XCTAssertEqual(PlantUMLPages.pageIndex(forLine: 3, in: pages), 0)   // gap → preceding
        XCTAssertEqual(PlantUMLPages.pageIndex(forLine: 0, in: pages), 0)
    }

    func testPageIndexEmpty() {
        XCTAssertNil(PlantUMLPages.pageIndex(forLine: 0, in: []))
    }
}
