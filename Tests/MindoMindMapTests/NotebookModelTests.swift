import XCTest
@testable import MindoMarkdown

/// Interactive/stateful tests for the notebook MODEL (the agent-authoring + run
/// + serialize-back layer), kept separate from the pure parser/format tests.
/// Execution + agent are stubbed so these stay fast and deterministic — no LLM,
/// no Lua VM.
@MainActor
final class NotebookModelTests: XCTestCase {

    /// Build a model with stub run/agent closures; `serialized` captures what the
    /// model writes back to the document.
    private func makeModel(
        text: String,
        serialized: @escaping (String) -> Void = { _ in },
        runOne: @escaping NotebookRunOne = { _, _ in ExecOutput(text: "") },
        runAll: @escaping NotebookRunAll = { _, _ in ExecOutputs() },
        runAgent: NotebookAgentRunner? = nil
    ) -> NotebookModel {
        NotebookModel(text: text, documentURL: nil,
                      runOne: runOne, runAll: runAll, runAgent: runAgent,
                      onSerialize: serialized)
    }

    func testRunCellStoresOutput() async {
        let model = makeModel(text: "```lua {exec id=c1}\nreturn 1\n```",
                              runOne: { src, _ in ExecOutput(text: src.contains("return 1") ? "7" : "?") })
        await model.run("c1")
        XCTAssertEqual(model.output(for: "c1")?.text, "7")
        XCTAssertTrue(model.running.isEmpty)
    }

    func testAgentBlockAuthorsIntoItsOwnResult() async {
        var lastSerialized = ""
        let model = makeModel(text: "# Notes\n", serialized: { lastSerialized = $0 },
            runAgent: { _, sink in
                sink.agentAddProse("Found that X relates to Y.")
                sink.agentAddCode("return 42", output: ExecOutput(text: "42"))
            })
        model.addAgent()
        let agentID = model.cells.last!.id
        model.updateText(agentID, "how do X and Y relate?")
        await model.runAgentCell(agentID)

        // No new top-level cells — the agent's work lives INSIDE the block.
        XCTAssertEqual(model.cells.count, 2)   // prose + agent
        let result = model.agentResult(of: agentID)
        XCTAssertTrue(result.contains("Found that X relates to Y."))
        XCTAssertTrue(result.contains("return 42"))   // ran code captured in the block
        XCTAssertTrue(lastSerialized.contains("mindo:agent"))
        XCTAssertFalse(model.agentBusy)
        XCTAssertTrue(model.running.isEmpty)
    }

    func testAgentBlockNoopWithoutRunnerOrPrompt() async {
        let model = makeModel(text: "# Notes\n")   // runAgent nil
        model.addAgent()
        let id = model.cells.last!.id
        model.updateText(id, "anything")
        await model.runAgentCell(id)               // no runner → no-op
        XCTAssertEqual(model.agentResult(of: id), "")
        XCTAssertFalse(model.agentBusy)
    }

    func testReloadFromExternalReparsesAndDropsStale() {
        let model = makeModel(text: "old prose")
        model.reload(from: "# New\n\n```lua {exec id=z}\nreturn 9\n```")
        XCTAssertEqual(model.cells.count, 2)
        XCTAssertTrue(model.cells.contains { if case .code = $0 { return true } else { return false } })
    }

    func testSelectionNavigation() {
        let model = makeModel(text: "a\n\n```lua {exec id=c}\nreturn 1\n```\n\nb")
        // prose-1, code c, prose-2
        XCTAssertEqual(model.cells.count, 3)
        model.selectFirstIfNeeded()
        XCTAssertEqual(model.selectedID, model.cells[0].id)
        model.selectNext()
        XCTAssertEqual(model.selectedID, model.cells[1].id)
        model.selectNext(); model.selectNext()   // clamp at last
        XCTAssertEqual(model.selectedID, model.cells[2].id)
        model.selectPrev()
        XCTAssertEqual(model.selectedID, model.cells[1].id)
    }

    func testDeleteSelectedReselectsNeighbor() {
        // Three cells (prose / code / prose — the scanner splits on code fences).
        let model = makeModel(text: "a\n\n```lua {exec id=x}\nreturn 1\n```\n\nc")
        XCTAssertEqual(model.cells.count, 3)
        let middleID = model.cells[1].id
        model.selectedID = middleID
        model.deleteSelected()
        XCTAssertEqual(model.cells.count, 2)
        XCTAssertNotNil(model.selectedID)
        XCTAssertNotEqual(model.selectedID, middleID)   // re-selected a neighbor
    }

    func testAddAfterSelectionSelectsNew() {
        let model = makeModel(text: "only")
        model.selectFirstIfNeeded()
        model.addAfterSelection { model.addCode(after: $0) }
        XCTAssertEqual(model.cells.count, 2)
        // The new code cell is selected and sits right after the original.
        XCTAssertEqual(model.selectedID, model.cells[1].id)
        if case .code = model.cells[1] {} else { XCTFail("new cell should be code") }
    }

    func testStaleAfterEditingCode() {
        let model = makeModel(text: "```lua {exec id=c1}\nreturn 1\n```")
        // No output cached yet → stale.
        XCTAssertTrue(model.isStale("c1"))
    }
}
