import XCTest
@testable import KepMarkdown

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

    func testAgentBlockRoundTrip() {
        let md = """
        Intro.

        <!--kep:agent {"prompt":"how do X and Y relate?"}-->
        Found a link via doc A.

        ```lua
        return 42
        ```
        <!--/kep:agent-->

        Outro.
        """
        let nb = NotebookFormat.parse(md)
        // prose, agent, prose
        XCTAssertEqual(nb.cells.count, 3)
        guard case .agent(_, let prompt, let result, _) = nb.cells[1] else { return XCTFail("cell1 agent") }
        XCTAssertEqual(prompt, "how do X and Y relate?")
        XCTAssertTrue(result.contains("Found a link via doc A."))
        XCTAssertTrue(result.contains("return 42"))
        // Round-trips (prompt + result preserved).
        let round = NotebookFormat.parse(NotebookFormat.serialize(nb))
        XCTAssertEqual(round.cells, nb.cells)
    }

    func testAgentBlockSourcesRoundTrip() {
        let nb = Notebook(cells: [.agent(id: "agent-1", prompt: "q", result: "findings",
                                         sources: ["Project Kep", "Roadmap"])])
        let round = NotebookFormat.parse(NotebookFormat.serialize(nb))
        guard case .agent(_, _, _, let sources) = round.cells.first else { return XCTFail("agent") }
        XCTAssertEqual(sources, ["Project Kep", "Roadmap"])
    }

    func testAgentPromptWithQuotesSurvives() {
        let nb = Notebook(cells: [.agent(id: "agent-1", prompt: "what about \"quotes\" & \nnewlines?", result: "r", sources: [])])
        let round = NotebookFormat.parse(NotebookFormat.serialize(nb))
        guard case .agent(_, let prompt, _, _) = round.cells.first else { return XCTFail("agent") }
        XCTAssertEqual(prompt, "what about \"quotes\" & \nnewlines?")
    }

    func testCodeCellOutputHashStable() {
        let nb = NotebookFormat.parse("```lua {exec id=x}\nreturn 1\n```")
        XCTAssertEqual(nb.cells[0].outputHash, MarkdownExecBlocks.hash("return 1"))
        // prose has no output hash
        XCTAssertNil(NotebookFormat.parse("just prose").cells[0].outputHash)
    }
}
