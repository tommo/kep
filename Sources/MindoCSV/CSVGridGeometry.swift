import CoreGraphics

/// Pure layout math for the spreadsheet grid (P1 of the custom CSVGridView).
/// Maps cell coordinates ⇄ rects in the document view's flipped coordinate
/// space (origin top-left, y grows downward), with a frozen column-header strip
/// across the top and a row-number gutter down the left. No AppKit/view state,
/// so the whole geometry is unit-testable.
public struct CSVGridGeometry: Equatable, Sendable {
    public var rowHeight: CGFloat
    public var headerHeight: CGFloat     // A/B/C column-header strip
    public var gutterWidth: CGFloat      // 1/2/3 row-number column
    public var columnWidths: [CGFloat]
    public var rowCount: Int

    public init(rowHeight: CGFloat = 22,
                headerHeight: CGFloat = 22,
                gutterWidth: CGFloat = 44,
                columnWidths: [CGFloat] = [],
                rowCount: Int = 0) {
        self.rowHeight = rowHeight
        self.headerHeight = headerHeight
        self.gutterWidth = gutterWidth
        self.columnWidths = columnWidths
        self.rowCount = rowCount
    }

    public var columnCount: Int { columnWidths.count }

    /// Full document-view size (header + gutter included).
    public var contentSize: CGSize {
        CGSize(width: gutterWidth + columnWidths.reduce(0, +),
               height: headerHeight + CGFloat(rowCount) * rowHeight)
    }

    // MARK: - Index → offset

    /// Left edge x of column `col` (absolute). Clamps out-of-range to the edge.
    public func columnX(_ col: Int) -> CGFloat {
        gutterWidth + columnWidths[0..<min(max(col, 0), columnCount)].reduce(0, +)
    }

    /// Top edge y of row `row` (absolute).
    public func rowY(_ row: Int) -> CGFloat {
        headerHeight + CGFloat(max(row, 0)) * rowHeight
    }

    public func cellRect(row: Int, col: Int) -> CGRect {
        guard col >= 0, col < columnCount else { return .zero }
        return CGRect(x: columnX(col), y: rowY(row), width: columnWidths[col], height: rowHeight)
    }

    public func columnHeaderRect(_ col: Int) -> CGRect {
        guard col >= 0, col < columnCount else { return .zero }
        return CGRect(x: columnX(col), y: 0, width: columnWidths[col], height: headerHeight)
    }

    public func rowGutterRect(_ row: Int) -> CGRect {
        CGRect(x: 0, y: rowY(row), width: gutterWidth, height: rowHeight)
    }

    public var cornerRect: CGRect {
        CGRect(x: 0, y: 0, width: gutterWidth, height: headerHeight)
    }

    /// Bounding rect of an inclusive cell range (for drawing the selection).
    public func rangeRect(top: Int, left: Int, bottom: Int, right: Int) -> CGRect {
        cellRect(row: top, col: left).union(cellRect(row: bottom, col: right))
    }

    // MARK: - Point → index (absolute content coords)

    /// Column index at absolute x (within the body, x ≥ gutterWidth). nil if in
    /// the gutter or past the last column.
    public func columnIndex(atX x: CGFloat) -> Int? {
        guard x >= gutterWidth else { return nil }
        var edge = gutterWidth
        for (i, w) in columnWidths.enumerated() {
            edge += w
            if x < edge { return i }
        }
        return nil
    }

    /// Row index at absolute y (within the body, y ≥ headerHeight).
    public func rowIndex(atY y: CGFloat) -> Int? {
        guard y >= headerHeight, rowHeight > 0 else { return nil }
        let r = Int((y - headerHeight) / rowHeight)
        return (r >= 0 && r < rowCount) ? r : nil
    }

    /// The body cell at an absolute point, or nil if the point lands in the
    /// header/gutter/corner or outside the grid.
    public func cell(at p: CGPoint) -> CSVCellRef? {
        guard let col = columnIndex(atX: p.x), let row = rowIndex(atY: p.y) else { return nil }
        return CSVCellRef(row: row, col: col)
    }
}
