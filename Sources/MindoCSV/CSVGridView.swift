import AppKit

/// The custom spreadsheet grid (chosen over NSTableView by the design workflow:
/// NSTableView selection is row/column-exclusive and can't hold an active cell
/// inside a rectangular range). A flipped document view inside the editor's
/// scroll view: it draws the cells, a frozen A/B/C column header, a 1/2/3 row
/// gutter and corner, the active-cell + range selection, and hosts an in-cell
/// field editor. Pure layout/selection math lives in CSVGridGeometry /
/// CSVSelectionModel; this class is the AppKit shell + drawing + input.
public final class CSVGridView: NSView, NSTextFieldDelegate {

    // MARK: - State (driven by the editor coordinator)

    public var sheet: CSVSheet = CSVSheet(document: CSVDocument())
    public private(set) var selection = CSVSelectionModel()

    /// Commit an edit: the coordinator routes this through sheet.setCell + undo
    /// + reload + the text binding.
    public var onCommitEdit: ((CSVCellRef, String) -> Void)?
    /// Selection changed (coordinator mirrors it + refreshes the status footer).
    public var onSelectionChange: ((CSVSelectionModel) -> Void)?
    /// Delete pressed over the selection (coordinator clears via undo).
    public var onClearRange: (([CSVCellRef]) -> Void)?
    /// Clipboard, routed through the responder chain so ⌘C/⌘X/⌘V work.
    public var onCopy: (() -> Void)?
    public var onCut: (() -> Void)?
    public var onPaste: (() -> Void)?

    @objc func copy(_ sender: Any?)  { onCopy?() }
    @objc func cut(_ sender: Any?)   { onCut?() }
    @objc func paste(_ sender: Any?) { onPaste?() }

    private var columnWidths: [CGFloat] = []
    private let defaultColumnWidth: CGFloat = 100
    private let rowHeight: CGFloat = 22
    private let headerHeight: CGFloat = 24
    private let gutterWidth: CGFloat = 48

    private var geometry = CSVGridGeometry()
    private var fieldEditor: NSTextField?
    private var editingRef: CSVCellRef?

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Reload

    /// Rebuild geometry from the sheet and resize the document view. Call after
    /// loading or any structural change.
    public func reload() {
        let cols = max(sheet.document.columnCount, 1)
        let rows = max(sheet.document.rows.count, 1)
        if columnWidths.count != cols {
            columnWidths = Array(repeating: defaultColumnWidth, count: cols)
        }
        geometry = CSVGridGeometry(rowHeight: rowHeight, headerHeight: headerHeight,
                                   gutterWidth: gutterWidth, columnWidths: columnWidths, rowCount: rows)
        selection.clamp(rows: rows, cols: cols)
        setFrameSize(geometry.contentSize)
        needsDisplay = true
    }

    public func setSelection(_ sel: CSVSelectionModel, notify: Bool = true) {
        selection = sel
        if notify { onSelectionChange?(selection) }
        scrollToActive()
        needsDisplay = true
    }

    private func value(_ r: CSVCellRef) -> String {
        let rows = sheet.document.rows
        guard r.row >= 0, r.row < rows.count, r.col >= 0, r.col < rows[r.row].count else { return "" }
        return rows[r.row][r.col]
    }

    private var rowCount: Int { max(sheet.document.rows.count, 1) }
    private var colCount: Int { max(sheet.document.columnCount, 1) }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        let vis = enclosingScrollView?.documentVisibleRect ?? bounds
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        drawCells(in: dirtyRect)
        drawSelection()
        // Frozen header + gutter painted last so body content scrolls under them.
        drawGutter(visible: vis)
        drawHeader(visible: vis)
        drawCorner(visible: vis)
    }

    private func drawCells(in dirtyRect: NSRect) {
        let gridColor = NSColor.gridColor
        let firstRow = geometry.rowIndex(atY: max(dirtyRect.minY, headerHeight)) ?? 0
        let lastRow = geometry.rowIndex(atY: dirtyRect.maxY) ?? (rowCount - 1)
        let firstCol = geometry.columnIndex(atX: max(dirtyRect.minX, gutterWidth)) ?? 0
        let lastCol = geometry.columnIndex(atX: dirtyRect.maxX) ?? (colCount - 1)
        guard firstRow <= lastRow, firstCol <= lastCol else { return }

        for row in firstRow...min(lastRow, rowCount - 1) {
            for col in firstCol...min(lastCol, colCount - 1) {
                let ref = CSVCellRef(row: row, col: col)
                let rect = geometry.cellRect(row: row, col: col)
                let style = sheet.style(at: ref)
                if let bg = style?.background.flatMap(Self.color(hex:)) {
                    bg.setFill(); rect.fill()
                }
                gridColor.setStroke()
                let path = NSBezierPath(rect: rect); path.lineWidth = 0.5; path.stroke()
                let text = value(ref)
                if !text.isEmpty { drawText(text, in: rect, style: style) }
            }
        }
    }

    private func drawText(_ text: String, in rect: CGRect, style: CSVCellStyle?) {
        var font = NSFont.systemFont(ofSize: 12)
        if let s = style, s.bold || s.italic {
            var traits: NSFontTraitMask = []
            if s.bold { traits.insert(.boldFontMask) }
            if s.italic { traits.insert(.italicFontMask) }
            font = NSFontManager.shared.convert(font, toHaveTrait: traits)
        }
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        switch style?.align {
        case "center": para.alignment = .center
        case "right":  para.alignment = .right
        default:       para.alignment = .left
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style?.textColor.flatMap(Self.color(hex:)) ?? NSColor.labelColor,
            .paragraphStyle: para,
        ]
        let inset = rect.insetBy(dx: 4, dy: 2)
        (text as NSString).draw(in: inset, withAttributes: attrs)
    }

    private func drawSelection() {
        let accent = NSColor.controlAccentColor
        let r = geometry.rangeRect(top: selection.top, left: selection.left,
                                   bottom: selection.bottom, right: selection.right)
        accent.withAlphaComponent(0.12).setFill(); r.fill()
        // Active-cell border.
        let active = geometry.cellRect(row: selection.active.row, col: selection.active.col)
        accent.setStroke()
        let border = NSBezierPath(rect: active.insetBy(dx: 0.5, dy: 0.5)); border.lineWidth = 2; border.stroke()
    }

    private func headerFillColor() -> NSColor { NSColor.windowBackgroundColor }

    private func drawHeader(visible vis: NSRect) {
        let y = vis.minY
        let strip = CGRect(x: vis.minX, y: y, width: vis.width, height: headerHeight)
        headerFillColor().setFill(); strip.fill()
        NSColor.gridColor.setStroke()
        let firstCol = geometry.columnIndex(atX: max(vis.minX, gutterWidth)) ?? 0
        let lastCol = geometry.columnIndex(atX: vis.maxX) ?? (colCount - 1)
        guard firstCol <= lastCol else { return }
        for col in firstCol...min(lastCol, colCount - 1) {
            let r = CGRect(x: geometry.columnX(col), y: y, width: columnWidths[col], height: headerHeight)
            NSBezierPath(rect: r).stroke()
            let inSel = col >= selection.left && col <= selection.right
            drawHeaderLabel(CSVCellRef.columnLabel(col), in: r, highlighted: inSel)
        }
    }

    private func drawGutter(visible vis: NSRect) {
        let x = vis.minX
        let strip = CGRect(x: x, y: vis.minY, width: gutterWidth, height: vis.height)
        headerFillColor().setFill(); strip.fill()
        NSColor.gridColor.setStroke()
        let firstRow = geometry.rowIndex(atY: max(vis.minY, headerHeight)) ?? 0
        let lastRow = geometry.rowIndex(atY: vis.maxY) ?? (rowCount - 1)
        guard firstRow <= lastRow else { return }
        for row in firstRow...min(lastRow, rowCount - 1) {
            let r = CGRect(x: x, y: geometry.rowY(row), width: gutterWidth, height: rowHeight)
            NSBezierPath(rect: r).stroke()
            let inSel = row >= selection.top && row <= selection.bottom
            drawHeaderLabel("\(row + 1)", in: r, highlighted: inSel)
        }
    }

    private func drawCorner(visible vis: NSRect) {
        let r = CGRect(x: vis.minX, y: vis.minY, width: gutterWidth, height: headerHeight)
        headerFillColor().setFill(); r.fill()
        NSColor.gridColor.setStroke(); NSBezierPath(rect: r).stroke()
    }

    private func drawHeaderLabel(_ s: String, in rect: CGRect, highlighted: Bool) {
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: highlighted ? .bold : .regular),
            .foregroundColor: highlighted ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ]
        let h = (s as NSString).size(withAttributes: attrs).height
        let r = CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        (s as NSString).draw(in: r, withAttributes: attrs)
    }

    static func color(hex: String) -> NSColor? {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        commitEditing(moveTo: nil)
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        let vis = enclosingScrollView?.documentVisibleRect ?? bounds

        // Pinned-header hit test (header/gutter float at the visible edges).
        let inHeader = p.y < vis.minY + headerHeight
        let inGutter = p.x < vis.minX + gutterWidth
        if inHeader && inGutter { return }                       // corner → no-op
        if inHeader, let col = geometry.columnIndex(atX: p.x) {   // whole column
            selection.moveActive(to: CSVCellRef(row: 0, col: col))
            selection.extend(to: CSVCellRef(row: rowCount - 1, col: col))
            finishSelectionChange(); return
        }
        if inGutter, let row = geometry.rowIndex(atY: p.y) {      // whole row
            selection.moveActive(to: CSVCellRef(row: row, col: 0))
            selection.extend(to: CSVCellRef(row: row, col: colCount - 1))
            finishSelectionChange(); return
        }
        guard let cell = clampedCell(at: p) else { return }
        if event.clickCount >= 2 { beginEditing(cell, seed: nil); return }
        if event.modifierFlags.contains(.shift) { selection.extend(to: cell) }
        else { selection.moveActive(to: cell) }
        finishSelectionChange()
    }

    public override func mouseDragged(with event: NSEvent) {
        guard editingRef == nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let cell = clampedCell(at: p) {
            selection.extend(to: cell)
            autoscroll(with: event)
            finishSelectionChange()
        }
    }

    /// Map a point to a cell, clamping to the grid so a drag past the edge
    /// still extends to the last row/column.
    private func clampedCell(at p: CGPoint) -> CSVCellRef? {
        let col = geometry.columnIndex(atX: p.x) ?? (p.x < gutterWidth ? 0 : colCount - 1)
        let row = geometry.rowIndex(atY: p.y) ?? (p.y < headerHeight ? 0 : rowCount - 1)
        return CSVCellRef(row: min(max(row, 0), rowCount - 1), col: min(max(col, 0), colCount - 1))
    }

    private func finishSelectionChange() {
        onSelectionChange?(selection)
        scrollToActive()
        needsDisplay = true
    }

    // MARK: - Keyboard

    public override func keyDown(with event: NSEvent) {
        guard editingRef == nil else { super.keyDown(with: event); return }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123: move(dRow: 0, dCol: -1, extend: shift)   // ←
        case 124: move(dRow: 0, dCol: 1, extend: shift)    // →
        case 125: move(dRow: 1, dCol: 0, extend: shift)    // ↓
        case 126: move(dRow: -1, dCol: 0, extend: shift)   // ↑
        case 36:  beginEditing(selection.active, seed: nil)            // Return → edit
        case 48:  move(dRow: 0, dCol: shift ? -1 : 1, extend: false)   // Tab
        case 51, 117:                                                  // Delete / fwd-Delete
            onClearRange?(selection.cells)
        case 53: break                                                 // Esc (no edit) → no-op
        default:
            // Type-to-edit: a printable character starts an edit seeded with it.
            if let chars = event.characters, chars.count == 1,
               let scalar = chars.unicodeScalars.first, scalar.value >= 32 {
                beginEditing(selection.active, seed: chars)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private func move(dRow: Int, dCol: Int, extend: Bool) {
        let cur = selection.active
        let next = CSVCellRef(row: min(max(cur.row + dRow, 0), rowCount - 1),
                              col: min(max(cur.col + dCol, 0), colCount - 1))
        if extend { selection.extend(to: next) } else { selection.moveActive(to: next) }
        finishSelectionChange()
    }

    private func scrollToActive() {
        var r = geometry.cellRect(row: selection.active.row, col: selection.active.col)
        // Pad by the frozen header/gutter so the active cell isn't hidden under them.
        r = r.insetBy(dx: -gutterWidth, dy: -headerHeight)
        scrollToVisible(r)
    }

    // MARK: - In-cell editing

    private func beginEditing(_ ref: CSVCellRef, seed: String?) {
        commitEditing(moveTo: nil)
        editingRef = ref
        let tf = NSTextField(frame: geometry.cellRect(row: ref.row, col: ref.col))
        tf.isBordered = true
        tf.focusRingType = .none
        tf.font = .systemFont(ofSize: 12)
        // Edit the formula SOURCE if present, else the baked value; a seed
        // (type-to-edit) replaces the content entirely.
        tf.stringValue = seed ?? sheet.formula(at: ref) ?? value(ref)
        tf.delegate = self
        addSubview(tf)
        fieldEditor = tf
        window?.makeFirstResponder(tf)
        if seed == nil { tf.currentEditor()?.selectAll(nil) }
        else { tf.currentEditor()?.selectedRange = NSRange(location: seed!.count, length: 0) }
    }

    /// Commit the active edit (if any) and optionally move the selection after.
    private func commitEditing(moveTo direction: (dRow: Int, dCol: Int)?) {
        guard let ref = editingRef, let tf = fieldEditor else { return }
        let text = tf.stringValue
        editingRef = nil
        fieldEditor = nil
        tf.removeFromSuperview()
        onCommitEdit?(ref, text)
        if let d = direction { move(dRow: d.dRow, dCol: d.dCol, extend: false) }
        window?.makeFirstResponder(self)
    }

    private func cancelEditing() {
        editingRef = nil
        fieldEditor?.removeFromSuperview()
        fieldEditor = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):    commitEditing(moveTo: (1, 0)); return true
        case #selector(NSResponder.insertTab(_:)):        commitEditing(moveTo: (0, 1)); return true
        case #selector(NSResponder.insertBacktab(_:)):    commitEditing(moveTo: (0, -1)); return true
        case #selector(NSResponder.cancelOperation(_:)):  cancelEditing(); return true
        default: return false
        }
    }
}
