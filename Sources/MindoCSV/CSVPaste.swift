import Foundation

/// A single cell write — shared by the paste planner and the replace planner
/// so both produce the same atomic, testable mutation list.
public struct CSVCellWrite: Equatable {
    public let row: Int
    public let column: Int
    public let value: String
    public init(row: Int, column: Int, value: String) {
        self.row = row
        self.column = column
        self.value = value
    }
}

/// The result of planning a paste: the exact cell writes plus the grid size
/// the document must grow to before applying them.
public struct CSVPastePlan: Equatable {
    public let writes: [CSVCellWrite]
    public let requiredRowCount: Int
    public let requiredColumnCount: Int
    public init(writes: [CSVCellWrite], requiredRowCount: Int, requiredColumnCount: Int) {
        self.writes = writes
        self.requiredRowCount = requiredRowCount
        self.requiredColumnCount = requiredColumnCount
    }
}

/// Pure planner for pasting a block at an anchor cell. GROW semantics (not
/// clamp): the grid extends down/right to fit, replacing javamind's fragile
/// one-stub-at-a-time growth that could throw out of bounds. `anchorRow` /
/// `anchorColumn` are DOCUMENT coordinates — the caller has already applied
/// any header offset.
public enum CSVPaste {
    public static func plan(
        block: CSVBlock,
        anchorRow: Int,
        anchorColumn: Int,
        currentRowCount: Int,
        currentColumnCount: Int
    ) -> CSVPastePlan {
        let r0 = max(0, anchorRow)
        let c0 = max(0, anchorColumn)
        var writes: [CSVCellWrite] = []
        for (i, row) in block.cells.enumerated() {
            for (j, value) in row.enumerated() {
                writes.append(CSVCellWrite(row: r0 + i, column: c0 + j, value: value))
            }
        }
        let neededRows = block.height > 0 ? max(currentRowCount, r0 + block.height) : currentRowCount
        let neededCols = block.width > 0 ? max(currentColumnCount, c0 + block.width) : currentColumnCount
        return CSVPastePlan(writes: writes, requiredRowCount: neededRows, requiredColumnCount: neededCols)
    }
}
