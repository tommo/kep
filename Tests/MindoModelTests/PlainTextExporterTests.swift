import XCTest
@testable import MindoModel

final class PlainTextExporterTests: XCTestCase {

    func testEmptyMapEmitsNothing() {
        XCTAssertEqual(PlainTextExporter.export(MindMap()), "")
    }

    func testTreeIndentsByTwoSpacesPerDepth() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        _ = a.addChild(text: "A1")
        _ = root.addChild(text: "B")
        let out = PlainTextExporter.export(map)
        XCTAssertEqual(out, """
        - Root
          - A
            - A1
          - B

        """)
    }

    func testNewlinesInTopicTextCollapseToSpaces() {
        // Bullet structure must stay single-line per entry.
        XCTAssertEqual(PlainTextExporter.escape("two\nlines"), "two lines")
    }

    func testBranchClonePattern() {
        // The branch-export flow takes a deep clone of the source topic and
        // wraps it as a fresh MindMap root. Verify that round-trips cleanly
        // through the plaintext exporter.
        let map = MindMap()
        let parent = Topic(text: "Outer")
        map.root = parent
        let branch = parent.addChild(text: "Branch")
        _ = branch.addChild(text: "Leaf")

        let branchMap = MindMap(root: branch.clone(deep: true))
        let out = PlainTextExporter.export(branchMap)
        XCTAssertEqual(out, """
        - Branch
          - Leaf

        """)
        // Source untouched.
        XCTAssertEqual(parent.children.count, 1)
        XCTAssertTrue(parent.children[0] === branch)
    }
}
