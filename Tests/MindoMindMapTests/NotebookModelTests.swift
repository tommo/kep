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

    func testAgentAuthorsRealCellsBelowTheBlock() async {
        var lastSerialized = ""
        let model = makeModel(text: "# Notes\n", serialized: { lastSerialized = $0 },
            runAgent: { _, _, _, sink in
                sink.agentAddProse("Found that X relates to Y.")
                sink.agentAddCode("return 42", output: ExecOutput(text: "42"))
            })
        model.addAgent()
        let agentID = model.cells.last!.id
        model.updateText(agentID, "how do X and Y relate?")
        await model.runAgentCell(agentID)

        // The agent authored REAL cells into the flow, right after the prompt:
        // [prose "# Notes", agent, prose "Found…", code "return 42"].
        XCTAssertEqual(model.cells.count, 4)
        let aIdx = model.cells.firstIndex { $0.id == agentID }!
        if case .prose(_, let t) = model.cells[aIdx + 1] {
            XCTAssertTrue(t.contains("Found that X relates to Y."))
        } else { XCTFail("expected an authored prose cell after the agent block") }
        if case .code(let cid, _, let code) = model.cells[aIdx + 2] {
            XCTAssertEqual(code, "return 42")
            XCTAssertEqual(model.output(for: cid)?.text, "42")   // authored output cached
        } else { XCTFail("expected an authored code cell after the agent block") }
        XCTAssertTrue(model.hasGenerated(agentID))
        XCTAssertTrue(lastSerialized.contains("return 42"))   // round-trips as real cells
        XCTAssertFalse(model.agentBusy)
        XCTAssertTrue(model.running.isEmpty)
    }

    func testAgentRerunReplacesPriorGeneration() async {
        let model = makeModel(text: "# n\n", runAgent: { _, _, _, sink in
            sink.agentAddProse("one")
        })
        model.addAgent()
        let id = model.cells.last!.id
        model.updateText(id, "q")
        await model.runAgentCell(id)
        XCTAssertEqual(model.cells.count, 3)   // prose, agent, authored prose
        await model.runAgentCell(id)
        XCTAssertEqual(model.cells.count, 3)   // prior generation replaced, not appended
    }

    func testAgentReceivesNotebookContextAbove() async {
        var seenContext = ""
        let model = makeModel(text: "Important premise about X.\n", runAgent: { _, context, _, sink in
            seenContext = context
            sink.agentAddProse("ok")
        })
        model.addAgent()
        let id = model.cells.last!.id
        model.updateText(id, "q")
        await model.runAgentCell(id)
        XCTAssertTrue(seenContext.contains("Important premise about X."))   // saw the cell above
    }

    func testAgentTraceAccumulatesAndClearsOnRerun() async {
        let model = makeModel(text: "# n\n", runAgent: { _, _, _, sink in
            sink.agentLog("🔎 searched: x")
            sink.agentLog("📄 read: Doc")
            sink.agentAddProse("done")
        })
        model.addAgent()
        let id = model.cells.last!.id
        model.updateText(id, "q")
        await model.runAgentCell(id)
        XCTAssertEqual(model.agentSteps(of: id), ["🔎 searched: x", "📄 read: Doc"])
        // Re-run clears the prior trace before logging again.
        await model.runAgentCell(id)
        XCTAssertEqual(model.agentSteps(of: id).count, 2)
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

    /// The shipped example notebook parses to the intended cell layout and
    /// round-trips (guards it against format drift).
    func testExampleNotebookParses() throws {
        // .../Tests/MindoMindMapTests/<this file> → repo root is three up.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Examples/espresso-kb/Extraction Research.mnb")
        let text = try String(contentsOf: url, encoding: .utf8)
        let nb = NotebookFormat.parse(text)

        // prose intro, 3 code cells, prose, 1 agent block.
        XCTAssertEqual(nb.codeCells.count, 3)
        XCTAssertTrue(nb.cells.contains { if case .agent = $0 { return true } else { return false } })
        XCTAssertTrue(nb.cells.contains { if case .prose = $0 { return true } else { return false } })
        if case .agent(_, let prompt, _, _) = nb.cells.first(where: { if case .agent = $0 { return true } else { return false } }) {
            XCTAssertTrue(prompt.contains("grind size"))   // the prompt survived the comment codec
        }
        // Idempotent serialize.
        XCTAssertEqual(NotebookFormat.serialize(NotebookFormat.parse(NotebookFormat.serialize(nb))),
                       NotebookFormat.serialize(nb))
    }
}
