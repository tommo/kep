import AppKit
import SwiftUI

/// Visual table editor for CSV documents. Wraps an `NSTableView` so we get
/// native cell editing, keyboard navigation, and selection. Toolbar above the
/// table exposes add/remove row/column.
public struct CSVEditor: NSViewRepresentable {
    @Binding public var text: String
    /// Native find/replace bar visibility, driven by ⌘F via the session.
    @Binding public var findBarVisible: Bool
    /// The document's on-disk URL, used to load + persist the extended layer
    /// (formulas + styling) in the `<name>.csv.sheet.json` sidecar. nil for an
    /// unsaved scratch document → no sidecar (the plain text still works).
    public var documentURL: URL?

    public init(text: Binding<String>, findBarVisible: Binding<Bool> = .constant(false),
                documentURL: URL? = nil) {
        self._text = text
        self._findBarVisible = findBarVisible
        self.documentURL = documentURL
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        // Same frame behaviour as every other editor: compress horizontally
        // (toolbar clips) rather than forcing a wide minimum that collapses the
        // sidebar in this mode.
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let toolbar = makeToolbar(coordinator: context.coordinator)
        toolbar.clipsToBounds = true
        toolbar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .lineBorder
        // The table scrolls horizontally, so it must NOT impose its content
        // width as a minimum on the editor — otherwise a wide CSV pushes the
        // whole detail pane out and squeezes the sidebar. Let it compress; the
        // horizontal scroller covers overflow.
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let grid = CSVGridView()
        let coord = context.coordinator
        grid.onCommitEdit     = { [weak coord] ref, val in coord?.commitGridEdit(ref, val) }
        grid.onSelectionChange = { [weak coord] sel in coord?.gridSelectionChanged(sel) }
        grid.onClearRange     = { [weak coord] cells in coord?.clearGridRange(cells) }
        grid.onCopy  = { [weak coord] in coord?.copyCells() }
        grid.onCut   = { [weak coord] in coord?.cutCells() }
        grid.onPaste = { [weak coord] in coord?.pasteCells() }
        grid.onAddColumn = { [weak coord] in coord?.appendColumn() }
        grid.onAddRow    = { [weak coord] in coord?.appendRow() }
        grid.onDropFile  = { [weak coord] ref, url in coord?.dropFile(ref, url) }
        // Right-click context menu — same coordinator selectors as the toolbar.
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = coord
            return i
        }
        menu.addItem(item("Insert Row Above",     #selector(Coordinator.insertRowBefore)))
        menu.addItem(item("Insert Row Below",     #selector(Coordinator.insertRowAfter)))
        menu.addItem(item("Delete Selected Rows", #selector(Coordinator.removeRow)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Insert Column Left",   #selector(Coordinator.insertColumnBefore)))
        menu.addItem(item("Insert Column Right",  #selector(Coordinator.insertColumnAfter)))
        menu.addItem(item("Delete Selected Cols", #selector(Coordinator.removeColumn)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Copy",  #selector(Coordinator.copyCells)))
        menu.addItem(item("Cut",   #selector(Coordinator.cutCells)))
        menu.addItem(item("Paste", #selector(Coordinator.pasteCells)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Clear Selected Cells", #selector(Coordinator.contextClearCells)))
        grid.menu = menu
        scroll.documentView = grid

        // Status footer — rows × cols, mirrors the markdown / plantuml /
        // mindmap editor footers.
        let footer = NSTextField(labelWithString: "")
        footer.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        footer.textColor = .secondaryLabelColor
        footer.alignment = .right
        footer.translatesAutoresizingMaskIntoConstraints = false

        let findBar = makeFindBar(coordinator: context.coordinator)
        findBar.isHidden = true
        findBar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        findBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)
        container.addSubview(scroll)
        container.addSubview(findBar)
        container.addSubview(footer)
        // Find bar collapses to zero height when hidden so it doesn't eat
        // table space; the coordinator flips isHidden + this constant.
        let findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
        context.coordinator.findBarHeightConstraint = findBarHeight

        // The toolbar and find bar are NSStackViews whose content (pull-downs,
        // the header checkbox, search/replace fields) is naturally wide. Pinning
        // them edge-to-edge at REQUIRED priority pushed that width up as the
        // editor's minimum, widening the detail pane and squeezing the sidebar
        // (fittingSize ignores clipping-resistance). Make their TRAILING pin
        // low-priority: they still stretch to fill when there's room, but no
        // longer dictate a minimum width. (Toolbar clips; the find bar's fields
        // shrink.) leading/clip stay required so they don't float off-screen.
        let toolbarTrailing = toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        toolbarTrailing.priority = .defaultLow
        let findBarTrailing = findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        findBarTrailing.priority = .defaultLow

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            toolbarTrailing,
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: findBar.topAnchor),
            findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            findBar.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            findBarTrailing,
            findBar.bottomAnchor.constraint(equalTo: footer.topAnchor),
            findBarHeight,
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            footer.heightAnchor.constraint(equalToConstant: 16),
        ])

        context.coordinator.grid = grid
        context.coordinator.parent = self
        context.coordinator.statusFooter = footer
        context.coordinator.loadFromText()
        context.coordinator.refreshStatusFooter()
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.serialize() != text {
            context.coordinator.loadFromText()   // rebuilds + reloads the grid
        }
        context.coordinator.setFindBarVisible(findBarVisible)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// Native find/replace bar: search field + prev/next + count, a case
    /// toggle, a replace field + Replace / Replace All, and Done. Hidden
    /// until ⌘F. Mirrors the markdown find bar's affordances using the
    /// pure CSVMatcher / CSVFindNavigator / CSVReplace modules.
    private func makeFindBar(coordinator: Coordinator) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.alignment = .centerY
        // Even hidden (height 0), this bar's WIDTH counts toward the editor's
        // fitting width — its fixed-width fields were forcing a ~700pt minimum
        // that widened the detail pane and squeezed the sidebar. Let it clip,
        // and make the field widths preferred-not-required (below) so they
        // compress instead of dictating the editor's minimum width.
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)

        func preferredWidth(_ view: NSView, _ w: CGFloat) {
            let c = view.widthAnchor.constraint(equalToConstant: w)
            c.priority = .defaultLow
            c.isActive = true
        }

        let find = NSSearchField()
        find.placeholderString = "Find in cells…"
        find.target = coordinator
        find.action = #selector(Coordinator.findFieldChanged)
        find.sendsSearchStringImmediately = false
        preferredWidth(find, 160)
        coordinator.findField = find

        let count = NSTextField(labelWithString: "")
        count.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        count.textColor = .secondaryLabelColor
        preferredWidth(count, 60)
        coordinator.findCountLabel = count

        func btn(_ title: String, _ tip: String, _ sel: Selector) -> NSButton {
            let b = NSButton(title: title, target: coordinator, action: sel)
            b.bezelStyle = .rounded
            b.toolTip = tip
            return b
        }
        let prev = btn("‹", "Previous match", #selector(Coordinator.findPrevious))
        let next = btn("›", "Next match", #selector(Coordinator.findNext))
        let caseToggle = NSButton(checkboxWithTitle: "Aa", target: coordinator, action: #selector(Coordinator.toggleFindCase))
        caseToggle.toolTip = "Case-sensitive"
        coordinator.findCaseToggle = caseToggle

        let replace = NSTextField(string: "")
        replace.placeholderString = "Replace…"
        preferredWidth(replace, 140)
        coordinator.replaceField = replace

        let replaceOne = btn("Replace", "Replace the current match", #selector(Coordinator.replaceOne))
        let replaceAll = btn("All", "Replace all matches", #selector(Coordinator.replaceAll))
        let done = btn("Done", "Close find bar (Esc)", #selector(Coordinator.closeFindBar))

        [find, count, prev, next, caseToggle, replace, replaceOne, replaceAll, NSView(), done]
            .forEach { stack.addArrangedSubview($0) }
        return stack
    }

    /// The Excel-style formula bar: a name box (the active cell's A1 ref — type
    /// an A1/range + Return to jump) and a wide formula field that always shows
    /// the selected cell's formula source (or its value), editable + Return to
    /// commit. Row/column operations moved to the grid's right-click menu (the
    /// old toolbar pull-downs were clunky).
    private func makeToolbar(coordinator: Coordinator) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)

        let nameBox = NSTextField(string: "A1")
        nameBox.alignment = .center
        nameBox.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        nameBox.toolTip = "Active cell — type an A1 reference or range to jump"
        nameBox.target = coordinator
        nameBox.action = #selector(Coordinator.nameBoxCommitted(_:))
        nameBox.widthAnchor.constraint(equalToConstant: 64).isActive = true
        nameBox.setContentHuggingPriority(.required, for: .horizontal)
        coordinator.nameBox = nameBox

        let fx = NSTextField(labelWithString: "ƒx")
        fx.textColor = .secondaryLabelColor

        let formula = NSTextField(string: "")
        formula.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        formula.placeholderString = "Value or formula — e.g. =A1+B1, =SUM(A1:A10)"
        formula.toolTip = "Formula / value of the active cell"
        formula.target = coordinator
        formula.action = #selector(Coordinator.formulaBarCommitted(_:))
        formula.setContentHuggingPriority(.defaultLow, for: .horizontal)
        coordinator.formulaField = formula

        stack.addArrangedSubview(nameBox)
        stack.addArrangedSubview(fx)
        stack.addArrangedSubview(formula)
        return stack
    }

    public final class Coordinator: NSObject {
        var parent: CSVEditor?
        var grid: CSVGridView?
        /// Mirror of the grid's selection, used by the toolbar/clipboard ops.
        var selection = CSVSelectionModel()
        weak var nameBox: NSTextField?
        weak var formulaField: NSTextField?
        weak var statusFooter: NSTextField?

        // Find/replace bar state.
        weak var findField: NSSearchField?
        weak var replaceField: NSTextField?
        weak var findCountLabel: NSTextField?
        weak var findCaseToggle: NSButton?
        var findBarHeightConstraint: NSLayoutConstraint?
        private var caseSensitiveFind = false
        private var currentMatch: CSVMatch?
        private var findBarShown = false
        /// The document + its extended layer (formulas + styling). `doc` is a
        /// read-only alias so the many `doc.xxx` edit/sort/paste call sites stay
        /// unchanged — they mutate the same CSVDocument instance the sheet holds.
        private var sheet = CSVSheet(document: CSVDocument())
        private var doc: CSVDocument { sheet.document }

        // MARK: - Wiring

        func loadFromText() {
            // Load the plain CSV (baked values) plus the sidecar (formulas +
            // styles), then re-bake the formula cells.
            // The spreadsheet grid has no "header row" concept (A/B/C label the
            // columns, 1/2/3 the rows), so every row is data — load with
            // hasHeader=false so grid rows == document rows == find/replace rows.
            sheet = CSVSheet.load(csv: parent?.text ?? "", sidecar: readSidecar(), hasHeader: false)
            sheet.recompute()
            // One-time migration: if an old visible sidecar exists, rewrite it as
            // the hidden dotfile and delete the legacy file so it stops showing.
            if let url = parent?.documentURL,
               FileManager.default.fileExists(atPath: CSVSheetExtras.legacySidecarURL(for: url).path) {
                writeSidecar()
            }
            grid?.sheet = sheet
            grid?.reload()
            syncFormulaBar()
        }

        // MARK: - Grid callbacks

        /// Commit an in-cell edit: route "=…" to the extended layer + recompute,
        /// literals to the CSV — all in one undo step — then reload + persist.
        func commitGridEdit(_ ref: CSVCellRef, _ text: String) {
            let current = sheet.formula(at: ref) ?? value(at: ref)
            guard current != text else { return }
            performUndoable(actionName: "Edit Cell") { sheet.setCell(ref, to: text) }
        }

        func gridSelectionChanged(_ sel: CSVSelectionModel) {
            selection = sel
            syncFormulaBar()
            refreshStatusFooter()
        }

        /// "+" tail affordances: append a row / column (one undo step + reload).
        func appendRow()    { performUndoable(actionName: "Add Row") { doc.appendRow() } }
        func appendColumn() { performUndoable(actionName: "Add Column") { doc.appendColumn() } }

        /// A workspace file was dropped onto a cell — store its path relative to
        /// the CSV file's directory, select the cell, and commit as one undo step.
        func dropFile(_ ref: CSVCellRef, _ fileURL: URL) {
            guard let docURL = parent?.documentURL else { return }
            let link = CSVLink.relativePath(of: fileURL, fromFileAt: docURL)
            var sel = selection
            sel.moveActive(to: ref)
            grid?.setSelection(sel)
            commitGridEdit(ref, link)
        }

        /// Reflect the active cell in the formula bar: its A1 ref in the name
        /// box and its formula SOURCE (or value) in the formula field — so the
        /// formula stays visible, not just its computed result.
        func syncFormulaBar() {
            let a = selection.active
            nameBox?.stringValue = a.a1
            formulaField?.stringValue = sheet.formula(at: a) ?? value(at: a)
        }

        /// Commit the formula bar's text to the active cell (Return in the field).
        @objc func formulaBarCommitted(_ sender: NSTextField) {
            commitGridEdit(selection.active, sender.stringValue)
            syncFormulaBar()
            grid?.window?.makeFirstResponder(grid)
        }

        /// Jump the selection to the A1 ref / range typed in the name box.
        @objc func nameBoxCommitted(_ sender: NSTextField) {
            let s = sender.stringValue.trimmingCharacters(in: .whitespaces)
            var sel: CSVSelectionModel?
            if let ref = CSVCellRef(a1: s) {
                sel = CSVSelectionModel(ref)
            } else if let cells = CSVCellRef.parseRange(s), let first = cells.first, let last = cells.last {
                var s2 = CSVSelectionModel(first); s2.extend(to: last); sel = s2
            }
            if let sel {
                selection = sel
                grid?.setSelection(sel)
            }
            syncFormulaBar()
            grid?.window?.makeFirstResponder(grid)
        }

        /// Delete over the selection — clear values + any formulas, one undo step.
        func clearGridRange(_ cells: [CSVCellRef]) {
            guard !cells.isEmpty else { return }
            performUndoable(actionName: cells.count > 1 ? "Clear Cells" : "Clear Cell") {
                for c in cells {
                    sheet.document.clearCell(row: c.row, column: c.col)
                    sheet.extras.setFormula(nil, at: c.a1)
                }
            }
        }

        private func value(at ref: CSVCellRef) -> String { sheet.value(at: ref) }

        func serialize() -> String { sheet.bakedCSV() }

        // MARK: - Extended-layer sidecar I/O

        /// Read the hidden `.<name>.csv.sheet.json` sidecar, falling back to the
        /// legacy non-hidden name for files written before the dotfile change.
        private func readSidecar() -> String? {
            guard let url = parent?.documentURL else { return nil }
            if let s = try? String(contentsOf: CSVSheetExtras.sidecarURL(for: url), encoding: .utf8) { return s }
            return try? String(contentsOf: CSVSheetExtras.legacySidecarURL(for: url), encoding: .utf8)
        }

        /// Write (or remove) the hidden sidecar to match the current extended
        /// layer, and always delete the legacy non-hidden sidecar so old visible
        /// files migrate away. No-op for unsaved scratch documents.
        private func writeSidecar() {
            guard let url = parent?.documentURL else { return }
            let fm = FileManager.default
            let sidecar = CSVSheetExtras.sidecarURL(for: url)
            let legacy = CSVSheetExtras.legacySidecarURL(for: url)
            if let json = sheet.sidecarJSON() {
                try? json.write(to: sidecar, atomically: true, encoding: .utf8)
            } else if fm.fileExists(atPath: sidecar.path) {
                try? fm.removeItem(at: sidecar)        // last extra cleared → drop it
            }
            if fm.fileExists(atPath: legacy.path) {
                try? fm.removeItem(at: legacy)         // clean up the old visible file
            }
        }

        private func notifyChange() {
            parent?.text = sheet.bakedCSV()
            writeSidecar()
        }

        /// Reload the table (optionally rebuilding the columns first) and
        /// echo the doc back to the binding. Every editing action funnels
        /// through here so the table view + binding stay in sync.
        private func applyChange(rebuildColumns rebuild: Bool = false) {
            grid?.sheet = sheet
            grid?.reload()
            notifyChange()
            refreshStatusFooter()
        }

        /// Recompute the status footer text — body row count + column count.
        /// Public-internal so makeNSView can fire it once after the initial
        /// loadFromText, plus applyChange uses it on every edit.
        func refreshStatusFooter() {
            guard let footer = statusFooter else { return }
            footer.stringValue = "\(doc.bodyRows.count) rows × \(doc.columnCount) cols"
        }

        // MARK: - Actions

        /// Insert a blank row above the first selected row (header
        /// excluded — selection indices are body-relative). With no
        /// selection, falls back to appending at the end so the button
        /// is never a dead-end.
        @objc func insertRowBefore() {
            let at = selection.top
            performUndoable(actionName: "Insert Row Before") { doc.insertRow(at: at) }
        }

        @objc func insertRowAfter() {
            let at = selection.bottom + 1
            performUndoable(actionName: "Insert Row After") { doc.insertRow(at: at) }
        }

        @objc func insertColumnBefore() {
            let at = selection.left
            performUndoable(actionName: "Insert Column Before", rebuildColumns: true) {
                doc.insertColumn(at: at)
            }
        }

        @objc func insertColumnAfter() {
            let at = selection.right + 1
            performUndoable(actionName: "Insert Column After", rebuildColumns: true) {
                doc.insertColumn(at: at)
            }
        }

        @objc func removeRow() {
            // Descending so removal indices stay valid as rows shift up.
            let rows = Array((selection.top...selection.bottom)).reversed()
            performUndoable(actionName: rows.count > 1 ? "Delete Rows" : "Delete Row") {
                for i in rows { doc.removeRow(at: i) }
            }
        }

        @objc func removeColumn() {
            let cols = Array((selection.left...selection.right)).reversed()
            performUndoable(actionName: cols.count > 1 ? "Delete Columns" : "Delete Column", rebuildColumns: true) {
                for i in cols { doc.removeColumn(at: i) }
            }
        }

        /// Clear every cell in the row × column intersection of the
        /// current selection. Skips already-empty cells so an
        /// empty-on-empty Delete doesn't burn an undo entry.
        func clearSelectedCells() {
            clearGridRange(selection.cells)
        }

        /// `@objc` shim so the right-click menu can target the same
        /// clear-cells logic the Delete-key path uses.
        @objc func contextClearCells() { clearSelectedCells() }

        // MARK: - Copy / Cut / Paste (multi-cell blocks)

        /// Cells under the current selection, as document coordinates — the
        /// same resolver Delete uses, reused so copy/cut/clear all agree.
        private func selectedCells() -> [(row: Int, column: Int)] {
            selection.cells.map { (row: $0.row, column: $0.col) }
        }

        /// Copy the selected block to the pasteboard as TSV. No-op (and no
        /// pasteboard write) when nothing is selected.
        @objc func copyCells() {
            let cells = selectedCells()
            guard !cells.isEmpty else { return }
            let block = CSVBlock.extract(from: doc.rows, cells: cells)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(CSVClipboard.serialize(block), forType: .string)
        }

        /// Copy then blank the selected cells — one undo step. Skips the undo
        /// entry when nothing actually changes (already-empty cells).
        @objc func cutCells() {
            let cells = selectedCells()
            guard !cells.isEmpty else { return }
            copyCells()
            performUndoable(actionName: cells.count > 1 ? "Cut Cells" : "Cut Cell") {
                _ = doc.clearCells(cells)
            }
        }

        /// Paste a TSV block from the pasteboard, anchored at the selected
        /// cell (top-left of the selection, or row 0 / col 0 with none).
        /// Grows the grid to fit.
        @objc func pasteCells() {
            guard let raw = NSPasteboard.general.string(forType: .string) else { return }
            let block = CSVClipboard.parse(raw)
            guard !block.isEmpty else { return }
            let anchorRow = selection.active.row
            let anchorCol = selection.active.col
            let plan = CSVPaste.plan(
                block: block, anchorRow: anchorRow, anchorColumn: anchorCol,
                currentRowCount: doc.rows.count, currentColumnCount: doc.columnCount)
            let willGrowColumns = plan.requiredColumnCount > doc.columnCount
            performUndoable(actionName: "Paste", rebuildColumns: willGrowColumns) {
                doc.applyPaste(plan)
            }
        }

        // MARK: - Find / Replace

        /// Reflect the binding-driven visibility: collapse/expand the bar and
        /// focus the search field on first show.
        func setFindBarVisible(_ visible: Bool) {
            guard visible != findBarShown else { return }
            findBarShown = visible
            findBarHeightConstraint?.constant = visible ? 30 : 0
            findField?.superview?.isHidden = !visible
            if visible {
                findField?.window?.makeFirstResponder(findField)
                refreshFindCount()
            } else {
                currentMatch = nil
            }
        }

        @objc func closeFindBar() {
            parent?.findBarVisible = false
            setFindBarVisible(false)
        }

        @objc func toggleFindCase(_ sender: NSButton) {
            caseSensitiveFind = sender.state == .on
            currentMatch = nil
            refreshFindCount()
        }

        @objc func findFieldChanged() {
            currentMatch = nil
            findNext()
        }

        /// Body-row matches (header excluded — its cells can't be selected).
        /// Match row indices are body/view-relative.
        private func findMatches() -> [CSVMatch] {
            let keyword = findField?.stringValue ?? ""
            return CSVMatcher.matches(in: doc.bodyRows, keyword: keyword, caseSensitive: caseSensitiveFind)
        }

        @objc func findNext()     { advanceFind(.forward) }
        @objc func findPrevious() { advanceFind(.backward) }

        private func advanceFind(_ direction: CSVFindDirection) {
            let matches = findMatches()
            guard let hit = CSVFindNavigator.next(matches: matches, after: currentMatch, direction: direction) else {
                currentMatch = nil
                refreshFindCount(matches)
                return
            }
            currentMatch = hit
            selectMatch(hit)
            refreshFindCount(matches)
        }

        /// Select + scroll to the matched cell's row. NSTableView row/column
        /// selection is mutually exclusive, so we highlight the whole row
        /// (the closest we can get to a single-cell highlight) and scroll it
        /// into view.
        private func selectMatch(_ match: CSVMatch) {
            let sel = CSVSelectionModel(CSVCellRef(row: match.row, col: match.column))
            selection = sel
            grid?.setSelection(sel)
        }

        private func refreshFindCount(_ matches: [CSVMatch]? = nil) {
            let all = matches ?? findMatches()
            guard let label = findCountLabel else { return }
            if (findField?.stringValue ?? "").isEmpty {
                label.stringValue = ""
            } else if all.isEmpty {
                label.stringValue = "0 found"
            } else if let cur = currentMatch, let idx = all.firstIndex(of: cur) {
                label.stringValue = "\(idx + 1) of \(all.count)"
            } else {
                label.stringValue = "\(all.count) found"
            }
        }

        @objc func replaceOne() {
            guard let match = currentMatch else { advanceFind(.forward); return }
            let keyword = findField?.stringValue ?? ""
            guard !keyword.isEmpty else { return }
            let replacement = replaceField?.stringValue ?? ""
            let docRow = doc.hasHeader ? match.row + 1 : match.row
            let current = (docRow < doc.rows.count && match.column < doc.rows[docRow].count) ? doc.rows[docRow][match.column] : ""
            guard CSVReplace.cellContains(current, keyword: keyword, caseSensitive: caseSensitiveFind) else {
                advanceFind(.forward); return
            }
            let updated = CSVReplace.replaceInCell(current, keyword: keyword, with: replacement, caseSensitive: caseSensitiveFind)
            performUndoable(actionName: "Replace", rebuildColumns: false) {
                doc.setCell(row: docRow, column: match.column, to: updated)
            }
            currentMatch = nil
            advanceFind(.forward)
        }

        @objc func replaceAll() {
            let keyword = findField?.stringValue ?? ""
            guard !keyword.isEmpty else { return }
            let replacement = replaceField?.stringValue ?? ""
            // Plan over body rows, then shift to document coordinates.
            let bodyWrites = CSVReplace.planReplaceAll(in: doc.bodyRows, keyword: keyword,
                                                       with: replacement, caseSensitive: caseSensitiveFind)
            guard !bodyWrites.isEmpty else { return }
            let offset = doc.hasHeader ? 1 : 0
            let writes = bodyWrites.map { CSVCellWrite(row: $0.row + offset, column: $0.column, value: $0.value) }
            performUndoable(actionName: writes.count > 1 ? "Replace All" : "Replace") {
                _ = doc.applyReplacements(writes)
            }
            currentMatch = nil
            refreshFindCount()
        }

        // MARK: - Undo

        /// Snapshot the current rows + hasHeader, run the mutation, then
        /// register an inverse that restores the snapshot. Sort changes use
        /// the same path; multi-select deletes too. Snapshot-based undo is
        /// simpler than per-mutation inverses and bulletproof for batch
        /// operations because the whole document state round-trips.
        private func performUndoable(
            actionName: String,
            rebuildColumns rebuild: Bool = false,
            mutate: () -> Void
        ) {
            let snapshot = doc.rows
            let hadHeader = doc.hasHeader
            mutate()
            registerUndo(actionName: actionName, snapshotRows: snapshot, hadHeader: hadHeader, rebuildColumns: rebuild)
            applyChange(rebuildColumns: rebuild)
        }

        private func registerUndo(actionName: String, snapshotRows: [[String]], hadHeader: Bool, rebuildColumns rebuild: Bool) {
            guard let undo = grid?.window?.undoManager else { return }
            let coordinator = self
            undo.setActionName(actionName)
            undo.registerUndo(withTarget: self) { _ in
                let redoSnapshot = coordinator.doc.rows
                let redoHadHeader = coordinator.doc.hasHeader
                coordinator.doc.rows = snapshotRows
                coordinator.doc.hasHeader = hadHeader
                coordinator.applyChange(rebuildColumns: rebuild)
                // Register the redo (inverse of the inverse) so ⌘⇧Z works.
                coordinator.registerUndo(actionName: actionName, snapshotRows: redoSnapshot, hadHeader: redoHadHeader, rebuildColumns: rebuild)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        return (index >= 0 && index < count) ? self[index] : nil
    }
}
