import XCTest
import MindoModel
@testable import MindoScript

/// The agent's CSV cell tools: name→URL resolution + dispatch to the host-
/// injected read/write closures. (The real cell logic lives in MindoCSV and is
/// covered by CSVSheetTests; here we verify the agent wiring with stubs.)
final class AgentCSVToolsTests: XCTestCase {

    private func tools(_ effects: AgentToolEffects) -> MindoAgentTools {
        MindoAgentTools(map: MindMap(root: Topic(text: "Root")),
                        allFiles: [URL(fileURLWithPath: "/ws/data.csv")],
                        effects: effects)
    }

    func testSetCsvCellRoutesToEffectAndRecordsChange() {
        var captured: (URL, String, String)?
        let effects = AgentToolEffects()
        effects.csvSetCell = { url, a1, value in captured = (url, a1, value); return true }
        let result = tools(effects).handle(
            name: "set_csv_cell",
            argumentsJSON: #"{"name":"data","cell":"B2","value":"=A1+A2"}"#)
        XCTAssertEqual(captured?.1, "B2")
        XCTAssertEqual(captured?.2, "=A1+A2")
        XCTAssertEqual(captured?.0.lastPathComponent, "data.csv")
        XCTAssertTrue(result.contains("Set B2"))
        XCTAssertTrue(effects.changedFiles.contains(URL(fileURLWithPath: "/ws/data.csv")))
    }

    func testReadCsvCellReturnsValue() {
        let effects = AgentToolEffects()
        effects.csvCellValue = { _, a1 in a1 == "C3" ? "42" : nil }
        let result = tools(effects).handle(
            name: "read_csv_cell", argumentsJSON: #"{"name":"data","cell":"C3"}"#)
        XCTAssertEqual(result, "42")
    }

    func testReadEmptyCell() {
        let effects = AgentToolEffects()
        effects.csvCellValue = { _, _ in "" }
        let result = tools(effects).handle(
            name: "read_csv_cell", argumentsJSON: #"{"name":"data","cell":"Z9"}"#)
        XCTAssertEqual(result, "(empty)")
    }

    func testUnknownDocument() {
        let effects = AgentToolEffects()
        effects.csvSetCell = { _, _, _ in true }
        let result = tools(effects).handle(
            name: "set_csv_cell", argumentsJSON: #"{"name":"nope","cell":"A1","value":"x"}"#)
        XCTAssertEqual(result, "not found")
    }

    func testUnavailableWhenNoEffectWired() {
        let result = tools(AgentToolEffects()).handle(
            name: "set_csv_cell", argumentsJSON: #"{"name":"data","cell":"A1","value":"x"}"#)
        XCTAssertTrue(result.contains("unavailable"))
    }

    func testWriteFailureReported() {
        let effects = AgentToolEffects()
        effects.csvSetCell = { _, _, _ in false }   // e.g. bad A1 ref
        let result = tools(effects).handle(
            name: "set_csv_cell", argumentsJSON: #"{"name":"data","cell":"!!","value":"x"}"#)
        XCTAssertTrue(result.contains("error"))
        XCTAssertFalse(effects.changedFiles.contains(URL(fileURLWithPath: "/ws/data.csv")))
    }

    func testCsvToolsInDescriptors() {
        let names = MindoAgentTools.descriptors.map(\.name)
        XCTAssertTrue(names.contains("set_csv_cell"))
        XCTAssertTrue(names.contains("read_csv_cell"))
    }
}
