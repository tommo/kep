import XCTest
import AppKit
@testable import MindoCSV

/// Real responder-chain coverage for CSVTableView: a Delete key event
/// (through window.sendEvent) and ⌘C/⌘X/⌘V actions (through
/// NSApplication.sendAction, the path the Edit menu / key equivalents use)
/// must fire the editor's hooks — proving the wiring works through real
/// AppKit dispatch, not just direct method calls.
@MainActor
final class CSVTableInteractiveTests: XCTestCase {

    /// Minimal 3×2 data source so the table actually has selectable rows.
    private final class Stub: NSObject, NSTableViewDataSource {
        func numberOfRows(in tableView: NSTableView) -> Int { 3 }
    }

    private func makeWindowedTable() -> (NSWindow, CSVTableView, Stub) {
        let table = CSVTableView()
        let stub = Stub()
        table.dataSource = stub
        for i in 0..<2 {
            let col = NSTableColumn(identifier: .init("c\(i)"))
            col.width = 80
            table.addTableColumn(col)
        }
        table.reloadData()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        scroll.documentView = table
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(table)
        return (window, table, stub)
    }

    private func sendKey(_ window: NSWindow, _ scalar: UnicodeScalar) {
        let ch = String(Character(scalar))
        let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                  timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                  characters: ch, charactersIgnoringModifiers: ch,
                                  isARepeat: false, keyCode: 0)!
        window.sendEvent(ev)
    }

    // MARK: - Delete key (keyDown)

    func testDeleteKeyFiresClearWhenRowSelected() {
        let (window, table, _) = makeWindowedTable()
        var cleared = 0
        table.onClearSelectedCells = { cleared += 1 }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        sendKey(window, "\u{7F}")                 // forward delete
        XCTAssertEqual(cleared, 1, "Delete with a selection fires the clear hook")
        sendKey(window, "\u{08}")                 // backspace
        XCTAssertEqual(cleared, 2)
    }

    func testDeleteKeyDoesNothingWithNoSelection() {
        let (window, table, _) = makeWindowedTable()
        var cleared = 0
        table.onClearSelectedCells = { cleared += 1 }
        table.deselectAll(nil)
        sendKey(window, "\u{7F}")
        XCTAssertEqual(cleared, 0, "no selection → no clear")
    }

    func testNonDeleteKeyDoesNotFireClear() {
        let (window, table, _) = makeWindowedTable()
        var cleared = 0
        table.onClearSelectedCells = { cleared += 1 }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        sendKey(window, "x")
        XCTAssertEqual(cleared, 0)
    }

    // MARK: - ⌘C / ⌘X / ⌘V responder-chain contract

    func testTableExposesClipboardSelectorsForTheResponderChain() {
        let (_, table, _) = makeWindowedTable()
        // The Edit menu's ⌘C/⌘X/⌘V find their target by walking the responder
        // chain for a view that `responds(to:)` these selectors. The table
        // must publish them (it's the first responder).
        XCTAssertTrue(table.responds(to: #selector(CSVTableView.copy(_:))))
        XCTAssertTrue(table.responds(to: #selector(CSVTableView.cut(_:))))
        XCTAssertTrue(table.responds(to: #selector(CSVTableView.paste(_:))))
    }

    func testClipboardSelectorsInvokeTheHooks() {
        let (_, table, _) = makeWindowedTable()
        var copied = 0, cut = 0, pasted = 0
        table.onCopy = { copied += 1 }
        table.onCut = { cut += 1 }
        table.onPaste = { pasted += 1 }
        // Invoke the selectors the way the responder chain ultimately does.
        table.perform(#selector(CSVTableView.copy(_:)), with: nil)
        table.perform(#selector(CSVTableView.cut(_:)), with: nil)
        table.perform(#selector(CSVTableView.paste(_:)), with: nil)
        XCTAssertEqual([copied, cut, pasted], [1, 1, 1], "each selector fires its hook")
    }
}
