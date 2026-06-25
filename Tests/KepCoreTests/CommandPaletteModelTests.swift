import XCTest
@testable import KepCore

final class CommandPaletteModelTests: XCTestCase {

    private func model(_ cmds: [AppCommand]) -> CommandPaletteModel {
        CommandPaletteModel(commands: cmds)
    }

    private let catalog: [AppCommand] = [
        AppCommand(id: "save", title: "Save"),
        AppCommand(id: "saveAll", title: "Save All"),
        AppCommand(id: "saveAs", title: "Save As"),
        AppCommand(id: "print", title: "Print", isEnabled: false),
        AppCommand(id: "find", title: "Find"),
    ]

    func testEmptyQueryReturnsAllInOrder() {
        let m = model(catalog)
        XCTAssertEqual(m.results.map { $0.item.id },
                       ["save", "saveAll", "saveAs", "print", "find"])
    }

    func testFuzzyRanksByTitle() {
        let m = model(catalog)
        m.setQuery("sal")            // matches "Save All"
        XCTAssertEqual(m.results.first?.item.id, "saveAll")
    }

    func testSetQueryLandsHighlightOnFirstEnabled() {
        // "rint" matches only the disabled Print command -> no enabled result,
        // selection stays 0 and selectedCommand is nil.
        let m = model(catalog)
        m.setQuery("rint")
        XCTAssertEqual(m.results.map { $0.item.id }, ["print"])
        XCTAssertNil(m.selectedCommand)
    }

    func testMoveSkipsDisabledRows() {
        // Order so a disabled command sits between two enabled ones.
        let cmds = [
            AppCommand(id: "a", title: "Apple"),
            AppCommand(id: "b", title: "Apricot", isEnabled: false),
            AppCommand(id: "c", title: "Avocado"),
        ]
        let m = model(cmds)
        XCTAssertEqual(m.selectedCommand?.id, "a")
        m.move(1)                    // should skip disabled "b" -> "c"
        XCTAssertEqual(m.selectedCommand?.id, "c")
        m.move(-1)                   // back up, skip "b" -> "a"
        XCTAssertEqual(m.selectedCommand?.id, "a")
    }

    func testMoveClampsAtEnds() {
        let m = model([AppCommand(id: "x", title: "Xenon")])
        m.move(-1)
        XCTAssertEqual(m.selection, 0)
        m.move(1)
        XCTAssertEqual(m.selection, 0)
    }

    func testSelectAtIgnoresDisabledRow() {
        let m = model(catalog)        // index 3 is disabled "print"
        m.select(at: 3)
        XCTAssertNotEqual(m.selection, 3)
        m.select(at: 1)               // enabled "saveAll"
        XCTAssertEqual(m.selection, 1)
        XCTAssertEqual(m.selectedCommand?.id, "saveAll")
    }

    func testNoMatchYieldsNilSelection() {
        let m = model(catalog)
        m.setQuery("zzzzz")
        XCTAssertTrue(m.results.isEmpty)
        XCTAssertNil(m.selectedCommand)
    }
}
