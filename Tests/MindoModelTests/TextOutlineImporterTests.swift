import XCTest
@testable import MindoModel

final class TextOutlineImporterTests: XCTestCase {

    func testFlatListBecomesRootWithSiblings() throws {
        let map = try TextOutlineImporter.parse("Root\nA\nB\nC\n")
        XCTAssertEqual(map.root?.text, "Root")
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B", "C"])
    }

    func testTwoSpaceIndentBuildsSubtree() throws {
        let text = """
        Root
          A
            A1
          B
        """
        let map = try TextOutlineImporter.parse(text)
        XCTAssertEqual(map.root?.text, "Root")
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B"])
        XCTAssertEqual(map.root?.children[0].children.map(\.text), ["A1"])
    }

    func testTabIndentBuildsSubtree() throws {
        let text = "Root\n\tA\n\t\tA1\n\tB\n"
        let map = try TextOutlineImporter.parse(text)
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B"])
        XCTAssertEqual(map.root?.children[0].children.map(\.text), ["A1"])
    }

    func testBulletMarkersAreStripped() throws {
        let text = """
        - Root
          - A
          * B
          + C
          • D
        """
        let map = try TextOutlineImporter.parse(text)
        XCTAssertEqual(map.root?.text, "Root")
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B", "C", "D"])
    }

    func testBlankLinesAreSkipped() throws {
        let map = try TextOutlineImporter.parse("Root\n\n  A\n\n\n  B\n")
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B"])
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try TextOutlineImporter.parse("   \n\n\t\n"))
    }

    func testCRLFLineEndingsHandled() throws {
        let map = try TextOutlineImporter.parse("Root\r\n  A\r\n  B\r\n")
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B"])
    }

    func testMixedZeroIndentLinesAttachToRoot() throws {
        // Two top-level lines after the first → both become children of
        // the first (single-rooted invariant).
        let map = try TextOutlineImporter.parse("Root\nA\nB\n")
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B"])
    }

    func testFourSpaceIndentDetected() throws {
        // First indent = 4 spaces → that's the unit; next level = 8 spaces.
        let text = "Root\n    A\n        A1\n    B\n"
        let map = try TextOutlineImporter.parse(text)
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B"])
        XCTAssertEqual(map.root?.children[0].children.map(\.text), ["A1"])
    }
}
