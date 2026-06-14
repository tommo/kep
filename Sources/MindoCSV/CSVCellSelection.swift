import Foundation

/// Resolves which document cells a "clear cells" action should touch given
/// an `NSTableView`'s row and column selection.
///
/// NSTableView makes row selection and column selection **mutually
/// exclusive** — selecting a column clears any selected rows and vice
/// versa — so an Excel-style "row × column intersection" never actually
/// has both sets populated at once. Rather than leave Delete a dead no-op
/// (the bug this fixes), we treat the active selection as the target:
///
/// - columns selected  → clear those columns across every body row
/// - rows selected     → clear those rows across every column
/// - both (defensive)  → the rectangular intersection
/// - neither           → nothing
///
/// Pure and table-free so the mapping is unit-testable. View-row indices
/// are body-relative; `hasHeader` shifts them to absolute document rows so
/// the header strip is never cleared.
public enum CSVCellSelection {
    public static func cellsToClear(
        selectedViewRows: IndexSet,
        selectedColumns: IndexSet,
        bodyRowCount: Int,
        columnCount: Int,
        hasHeader: Bool
    ) -> [(row: Int, column: Int)] {
        guard bodyRowCount > 0, columnCount > 0 else { return [] }

        let rows: [Int]
        if !selectedViewRows.isEmpty {
            rows = selectedViewRows.filter { $0 >= 0 && $0 < bodyRowCount }
        } else if !selectedColumns.isEmpty {
            rows = Array(0..<bodyRowCount)          // whole columns
        } else {
            return []
        }

        let columns: [Int]
        if !selectedColumns.isEmpty {
            columns = selectedColumns.filter { $0 >= 0 && $0 < columnCount }
        } else {
            columns = Array(0..<columnCount)        // whole rows
        }

        var cells: [(row: Int, column: Int)] = []
        cells.reserveCapacity(rows.count * columns.count)
        for viewRow in rows {
            let docRow = hasHeader ? viewRow + 1 : viewRow
            for col in columns {
                cells.append((row: docRow, column: col))
            }
        }
        return cells
    }
}
