import Foundation

/// A rectangular block of cell strings — the unit that is copied, cut, and
/// pasted. Pure and table-free so block extraction and geometry are
/// unit-testable without an NSTableView. `cells` is padded to a full
/// rectangle (gaps filled with "") so paste mapping is unambiguous, which
/// also fixes javamind's null-drop bug where a sparse selection collapsed
/// and lost column alignment.
public struct CSVBlock: Equatable {
    public let cells: [[String]]

    public init(cells: [[String]]) {
        self.cells = cells
    }

    public var height: Int { cells.count }
    public var width: Int { cells.map(\.count).max() ?? 0 }
    public var isEmpty: Bool {
        cells.isEmpty || cells.allSatisfy { $0.allSatisfy(\.isEmpty) }
    }

    /// Extract the bounding rectangle of `cells` (document-row, column) from
    /// `rows`, filling any cell inside the rectangle that wasn't selected —
    /// or lies past a short row — with "". Returns an empty block for an
    /// empty selection.
    public static func extract(from rows: [[String]], cells: [(row: Int, column: Int)]) -> CSVBlock {
        guard !cells.isEmpty else { return CSVBlock(cells: []) }
        let rowsSel = cells.map(\.row)
        let colsSel = cells.map(\.column)
        let minRow = rowsSel.min()!, maxRow = rowsSel.max()!
        let minCol = colsSel.min()!, maxCol = colsSel.max()!
        // Mark which cells were actually selected so gaps become "".
        let selected = Set(cells.map { CellKey($0.row, $0.column) })

        var block: [[String]] = []
        block.reserveCapacity(maxRow - minRow + 1)
        for r in minRow...maxRow {
            var rowCells: [String] = []
            rowCells.reserveCapacity(maxCol - minCol + 1)
            for c in minCol...maxCol {
                if selected.contains(CellKey(r, c)),
                   r >= 0, r < rows.count, c >= 0, c < rows[r].count {
                    rowCells.append(rows[r][c])
                } else {
                    rowCells.append("")
                }
            }
            block.append(rowCells)
        }
        return CSVBlock(cells: block)
    }

    private struct CellKey: Hashable {
        let r: Int, c: Int
        init(_ r: Int, _ c: Int) { self.r = r; self.c = c }
    }
}
