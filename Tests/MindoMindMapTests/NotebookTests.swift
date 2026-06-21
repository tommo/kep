import XCTest
@testable import MindoMarkdown

final class NotebookTests: XCTestCase {

    func testSegmentsProseAndCodeInOrder() {
        let md = """
        # Title

        Intro prose.

        ```lua {exec id=calc}
        return 1 + 2
        ```

        Closing prose.
        """
        let nb = NotebookFormat.parse(md)
        XCTAssertEqual(nb.cells.count, 3)
        guard case .prose(_, let p1) = nb.cells[0] else { return XCTFail("cell0 prose") }
        XCTAssertTrue(p1.contains("# Title"))
        guard case .code(let id, let lang, let code) = nb.cells[1] else { return XCTFail("cell1 code") }
        XCTAssertEqual(id, "calc")
        XCTAssertEqual(lang, "lua")
        XCTAssertEqual(code, "return 1 + 2")
        guard case .prose = nb.cells[2] else { return XCTFail("cell2 prose") }
    }

    func testPlainCodeBlockStaysProse() {
        // A non-exec fenced block is regular markdown, not a cell.
        let md = "```python\nprint(1)\n```"
        let nb = NotebookFormat.parse(md)
        XCTAssertEqual(nb.cells.count, 1)
        guard case .prose = nb.cells[0] else { return XCTFail("should be prose") }
        XCTAssertTrue(nb.codeCells.isEmpty)
    }

    func testRoundTripPreservesCells() {
        let md = """
        Lead in.

        ```lua {exec id=a}
        return 1
        ```

        Middle.

        ```lua {exec id=b}
        return 2
        ```
        """
        let nb = NotebookFormat.parse(md)
        let round = NotebookFormat.parse(NotebookFormat.serialize(nb))
        XCTAssertEqual(round.cells, nb.cells)
        XCTAssertEqual(round.codeCells.count, 2)
    }

    func testCodeCellOutputHashStable() {
        let nb = NotebookFormat.parse("```lua {exec id=x}\nreturn 1\n```")
        XCTAssertEqual(nb.cells[0].outputHash, MarkdownExecBlocks.hash("return 1"))
        // prose has no output hash
        XCTAssertNil(NotebookFormat.parse("just prose").cells[0].outputHash)
    }
}
