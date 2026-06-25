import Foundation

/// In-memory representation of a CSV document. Rows are arrays of field
/// strings; the first row, when treated as headers, drives column titles in
/// the visual editor. Parsing follows RFC 4180 with two tweaks for real-world
/// files: lone CR/LF terminators are accepted, and trailing blank lines are
/// dropped.
public final class CSVDocument {
    public var rows: [[String]]
    public var hasHeader: Bool

    public init(rows: [[String]] = [[""]], hasHeader: Bool = true) {
        self.rows = rows.isEmpty ? [[""]] : rows
        self.hasHeader = hasHeader
    }

    /// Number of columns the editor should display. Derived from the widest row.
    public var columnCount: Int {
        rows.map(\.count).max() ?? 1
    }

    /// Header strings — falls back to "Column 1, 2, …" when `hasHeader` is false.
    public var headers: [String] {
        if hasHeader, let first = rows.first { return first }
        return (0..<columnCount).map { "Column \($0 + 1)" }
    }

    /// Body rows (skips the header when `hasHeader` is true).
    public var bodyRows: [[String]] {
        hasHeader ? Array(rows.dropFirst()) : rows
    }

    /// Pad short rows so every row has `columnCount` cells. Used after editing
    /// rows of uneven length so the table view sees a clean rectangle.
    public func normalize() {
        let cols = columnCount
        for i in 0..<rows.count where rows[i].count < cols {
            rows[i].append(contentsOf: Array(repeating: "", count: cols - rows[i].count))
        }
    }

    // MARK: - Mutations

    public func setCell(row: Int, column: Int, to value: String) {
        guard row >= 0, row < rows.count else { return }
        if column >= rows[row].count {
            rows[row].append(contentsOf: Array(repeating: "", count: column - rows[row].count + 1))
        }
        rows[row][column] = value
    }

    /// Clear a single cell's value to "". Convenience over setCell that
    /// makes intent explicit at call sites and short-circuits when the
    /// cell is already empty so the editor doesn't burn an undo entry
    /// on a no-op delete.
    @discardableResult
    public func clearCell(row: Int, column: Int) -> Bool {
        guard row >= 0, row < rows.count else { return false }
        guard column >= 0 else { return false }
        if column >= rows[row].count { return false }
        if rows[row][column].isEmpty { return false }
        rows[row][column] = ""
        return true
    }

    /// Clear the cells at every (row, column) pair in `cells`. Returns
    /// the number of cells that actually changed (skipped already-empty
    /// cells + out-of-range coordinates). One call from the editor's
    /// Delete-key handler so the bulk clear becomes a single undo step.
    @discardableResult
    public func clearCells(_ cells: [(row: Int, column: Int)]) -> Int {
        var changed = 0
        for cell in cells {
            if clearCell(row: cell.row, column: cell.column) { changed += 1 }
        }
        return changed
    }

    public func appendRow() {
        rows.append(Array(repeating: "", count: columnCount))
    }

    public func appendColumn() {
        let newCount = columnCount + 1
        for i in rows.indices {
            if rows[i].count < newCount { rows[i].append("") }
        }
    }

    /// Insert a blank row at `index`. Out-of-bounds indices are clamped:
    /// negative → 0, past-end → append. Mirrors mindolph's csv.menu
    /// "Insert Before / After" entries.
    public func insertRow(at index: Int) {
        let blank = Array(repeating: "", count: columnCount)
        let clamped = max(0, min(index, rows.count))
        rows.insert(blank, at: clamped)
    }

    /// Insert a blank column at `index`. Out-of-bounds indices clamp the
    /// same way as `insertRow`. Every row grows by one cell so the
    /// column count stays consistent across the table.
    public func insertColumn(at index: Int) {
        let cols = columnCount
        let clamped = max(0, min(index, cols))
        for i in rows.indices {
            // Pad short rows out to the current column count first so the
            // new column lands at the same logical position in every row.
            if rows[i].count < cols {
                rows[i].append(contentsOf: Array(repeating: "", count: cols - rows[i].count))
            }
            rows[i].insert("", at: min(clamped, rows[i].count))
        }
    }

    public func removeRow(at index: Int) {
        guard rows.count > 1, index >= 0, index < rows.count else { return }
        rows.remove(at: index)
    }

    public func removeColumn(at index: Int) {
        guard columnCount > 1, index >= 0 else { return }
        for i in rows.indices where index < rows[i].count {
            rows[i].remove(at: index)
        }
    }

    /// Sort body rows by the value in `columnIndex`. Header row (if any)
    /// stays put. Numeric values sort numerically when both cells parse,
    /// otherwise the comparison falls back to localized string ordering
    /// (case-insensitive). `ascending: nil` clears any prior sort by
    /// re-reading the rows from disk would be ideal, but the editor
    /// drives that path — this method just orders the in-memory body.
    public func sort(byColumn columnIndex: Int, ascending: Bool) {
        guard columnIndex >= 0, columnIndex < columnCount else { return }
        let header = hasHeader && !rows.isEmpty ? [rows[0]] : []
        var body = bodyRows
        body.sort { lhs, rhs in
            let a = columnIndex < lhs.count ? lhs[columnIndex] : ""
            let b = columnIndex < rhs.count ? rhs[columnIndex] : ""
            // Try numeric comparison when both sides parse as Double.
            if let na = Double(a), let nb = Double(b) {
                return ascending ? na < nb : na > nb
            }
            let order = a.localizedCaseInsensitiveCompare(b)
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        rows = header + body
    }

    // MARK: - Block paste / replace (apply a pure plan)

    /// Grow the grid to the plan's required size, then apply every cell
    /// write. Returns true when the column count increased so the editor
    /// knows to rebuild its NSTableView columns.
    @discardableResult
    public func applyPaste(_ plan: CSVPastePlan) -> Bool {
        let oldColumnCount = columnCount
        while rows.count < plan.requiredRowCount { appendRow() }
        while columnCount < plan.requiredColumnCount { appendColumn() }
        for w in plan.writes {
            setCell(row: w.row, column: w.column, to: w.value)
        }
        return columnCount > oldColumnCount
    }

    /// Apply a list of replace writes. Returns the number applied (0 lets the
    /// editor skip burning an undo entry on a no-op replace-all).
    @discardableResult
    public func applyReplacements(_ writes: [CSVCellWrite]) -> Int {
        // Count only writes that actually land — setCell silently ignores an
        // out-of-bounds row, so returning writes.count would over-report.
        var applied = 0
        for w in writes {
            guard w.row >= 0, w.row < rows.count else { continue }
            setCell(row: w.row, column: w.column, to: w.value)
            applied += 1
        }
        return applied
    }

    // MARK: - Parsing & serialization

    /// Parse RFC-4180 CSV text into a `CSVDocument`. Always succeeds; malformed
    /// quoting is treated leniently (best-effort parse).
    ///
    /// We iterate over `UnicodeScalar` rather than `Character` because Swift
    /// treats `\r\n` as a single grapheme cluster — that would prevent us from
    /// matching `"\r"` and `"\n"` cases independently.
    public static func parse(_ text: String, hasHeader: Bool = true) -> CSVDocument {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false

        // Nested helpers that mutate the loop's working buffers.
        func flushField() {
            current.append(field)
            field.removeAll(keepingCapacity: true)
        }
        func flushRow() {
            flushField()
            rows.append(current)
            current.removeAll(keepingCapacity: true)
        }

        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        field.append("\"")          // doubled quote → literal "
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.unicodeScalars.append(c)
                i += 1
                continue
            }

            switch c {
            case ",":
                flushField()
            case "\r":
                flushRow()
                if i + 1 < scalars.count, scalars[i + 1] == "\n" {
                    i += 1                      // swallow LF following CR
                }
            case "\n":
                flushRow()
            case "\"":
                if field.isEmpty {
                    inQuotes = true
                } else {
                    field.unicodeScalars.append(c)  // tolerate stray mid-field quotes
                }
            default:
                field.unicodeScalars.append(c)
            }
            i += 1
        }

        // Flush whatever's left in `field` / `current`.
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }
        // Drop trailing blank rows (single empty cell).
        while let last = rows.last, last.count <= 1, last.first?.isEmpty ?? true {
            rows.removeLast()
        }
        if rows.isEmpty { rows = [[""]] }

        let doc = CSVDocument(rows: rows, hasHeader: hasHeader)
        doc.normalize()
        return doc
    }

    /// Serialize back to RFC-4180 CSV. Uses `\n` line terminators.
    public func serialize() -> String {
        rows.map { row in
            row.map(Self.escapeField).joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }

    private static func escapeField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}
