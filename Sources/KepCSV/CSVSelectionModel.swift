/// The spreadsheet selection: a single active cell plus an anchor; the selected
/// range is their bounding box (a single cell when anchor == active). Pure value
/// type in absolute cell coords, so the keyboard/mouse transforms are testable
/// without a view. Replaces the row/column-oriented CSVCellSelection for the
/// custom grid.
public struct CSVSelectionModel: Equatable, Sendable {
    /// The fixed corner of a range (set on click / move); shift-extend keeps it.
    public private(set) var anchor: CSVCellRef
    /// The "live" cell — where typing/editing happens and arrows move from.
    public private(set) var active: CSVCellRef

    public init(_ ref: CSVCellRef = CSVCellRef(row: 0, col: 0)) {
        anchor = ref
        active = ref
    }

    public var isSingle: Bool { anchor == active }
    public var top: Int { min(anchor.row, active.row) }
    public var bottom: Int { max(anchor.row, active.row) }
    public var left: Int { min(anchor.col, active.col) }
    public var right: Int { max(anchor.col, active.col) }

    public func contains(_ r: CSVCellRef) -> Bool {
        r.row >= top && r.row <= bottom && r.col >= left && r.col <= right
    }

    /// Move the active cell and collapse the range onto it (a plain click /
    /// unshifted arrow).
    public mutating func moveActive(to r: CSVCellRef) {
        anchor = r
        active = r
    }

    /// Extend the range to `r`, keeping the anchor fixed (shift-click /
    /// shift-arrow / drag).
    public mutating func extend(to r: CSVCellRef) {
        active = r
    }

    /// Every cell in the selected box, row-major.
    public var cells: [CSVCellRef] {
        var out: [CSVCellRef] = []
        for row in top...bottom { for col in left...right { out.append(CSVCellRef(row: row, col: col)) } }
        return out
    }

    /// Clamp both anchor and active into a `rows × cols` grid (after the grid
    /// shrinks, e.g. row delete) so the selection never points off-grid.
    public mutating func clamp(rows: Int, cols: Int) {
        guard rows > 0, cols > 0 else { return }
        func c(_ r: CSVCellRef) -> CSVCellRef {
            CSVCellRef(row: min(max(r.row, 0), rows - 1), col: min(max(r.col, 0), cols - 1))
        }
        anchor = c(anchor)
        active = c(active)
    }
}
