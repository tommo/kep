import AppKit
import SwiftUI

/// Visual table editor for CSV documents. Wraps an `NSTableView` so we get
/// native cell editing, keyboard navigation, and selection. Toolbar above the
/// table exposes add/remove row/column.
public struct CSVEditor: NSViewRepresentable {
    @Binding public var text: String
    /// Native find/replace bar visibility, driven by ⌘F via the session.
    @Binding public var findBarVisible: Bool

    public init(text: Binding<String>, findBarVisible: Binding<Bool> = .constant(false)) {
        self._text = text
        self._findBarVisible = findBarVisible
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
        let table = CSVTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        table.allowsColumnResizing = true
        table.allowsColumnReordering = false
        table.allowsMultipleSelection = true
        // Without this, NSTableView ignores every selectColumnIndexes call,
        // so selectedColumnIndexes stays permanently empty — which silently
        // killed Delete-to-clear, Delete Column, and the insert-at-selection
        // column ops (they all read selectedColumnIndexes). Clicking a column
        // header now selects the column so those actions have something to
        // act on. (mindolph parity: csv column ops operate on a selection.)
        table.allowsColumnSelection = true
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        // Delete / Backspace clears the cells under selection — mindolph
        // parity for csv.menu.delete.cell. Closure rather than delegate
        // protocol so the subclass stays self-contained.
        table.onClearSelectedCells = { [weak coordinator = context.coordinator] in
            coordinator?.clearSelectedCells()
        }
        table.onCopy  = { [weak coordinator = context.coordinator] in coordinator?.copyCells() }
        table.onCut   = { [weak coordinator = context.coordinator] in coordinator?.cutCells() }
        table.onPaste = { [weak coordinator = context.coordinator] in coordinator?.pasteCells() }
        // Right-click context menu — mirrors mindolph csv.menu's row +
        // cell entries. Items dispatch to the same coordinator selectors
        // the toolbar buttons already use; NSTableView updates the
        // selection on right-click before the menu shows so the actions
        // read the right rows / columns.
        let menu = NSMenu()
        let coord = context.coordinator
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
        table.menu = menu
        scroll.documentView = table

        // Status footer — rows × cols, mirrors the markdown / plantuml /
        // mindmap editor footers.
        let footer = NSTextField(labelWithString: "")
        footer.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        footer.textColor = .secondaryLabelColor
        footer.alignment = .right
        footer.translatesAutoresizingMaskIntoConstraints = false

        let findBar = makeFindBar(coordinator: context.coordinator)
        findBar.isHidden = true

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
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: findBar.topAnchor),
            findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            findBar.bottomAnchor.constraint(equalTo: footer.topAnchor),
            findBarHeight,
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            footer.heightAnchor.constraint(equalToConstant: 16),
        ])

        context.coordinator.tableView = table
        context.coordinator.parent = self
        context.coordinator.statusFooter = footer
        context.coordinator.loadFromText()
        context.coordinator.rebuildColumns()
        context.coordinator.refreshStatusFooter()
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.serialize() != text {
            context.coordinator.loadFromText()
            context.coordinator.rebuildColumns()
            context.coordinator.tableView?.reloadData()
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

        let find = NSSearchField()
        find.placeholderString = "Find in cells…"
        find.target = coordinator
        find.action = #selector(Coordinator.findFieldChanged)
        find.sendsSearchStringImmediately = false
        find.widthAnchor.constraint(equalToConstant: 160).isActive = true
        coordinator.findField = find

        let count = NSTextField(labelWithString: "")
        count.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        count.textColor = .secondaryLabelColor
        count.widthAnchor.constraint(equalToConstant: 60).isActive = true
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
        replace.widthAnchor.constraint(equalToConstant: 140).isActive = true
        coordinator.replaceField = replace

        let replaceOne = btn("Replace", "Replace the current match", #selector(Coordinator.replaceOne))
        let replaceAll = btn("All", "Replace all matches", #selector(Coordinator.replaceAll))
        let done = btn("Done", "Close find bar (Esc)", #selector(Coordinator.closeFindBar))

        [find, count, prev, next, caseToggle, replace, replaceOne, replaceAll, NSView(), done]
            .forEach { stack.addArrangedSubview($0) }
        return stack
    }

    private func makeToolbar(coordinator: Coordinator) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        // Let the toolbar clip rather than force the editor (and thus the whole
        // detail pane) wider — keeps the sidebar width stable across modes.
        // See the longer note in PlantUMLEditor.makeToolbar.
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)

        func button(_ title: String, _ tooltip: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: coordinator, action: action)
            b.bezelStyle = .rounded
            b.toolTip = tooltip
            return b
        }

        stack.addArrangedSubview(button("+ Row", "Append a new row", #selector(Coordinator.addRow)))
        stack.addArrangedSubview(button("↑ Row", "Insert row above selection", #selector(Coordinator.insertRowBefore)))
        stack.addArrangedSubview(button("↓ Row", "Insert row below selection", #selector(Coordinator.insertRowAfter)))
        stack.addArrangedSubview(button("− Row", "Remove the selected row", #selector(Coordinator.removeRow)))
        stack.addArrangedSubview(button("+ Column", "Append a new column", #selector(Coordinator.addColumn)))
        stack.addArrangedSubview(button("← Col", "Insert column left of selection", #selector(Coordinator.insertColumnBefore)))
        stack.addArrangedSubview(button("→ Col", "Insert column right of selection", #selector(Coordinator.insertColumnAfter)))
        stack.addArrangedSubview(button("− Column", "Remove the selected column", #selector(Coordinator.removeColumn)))
        stack.addArrangedSubview(NSView())
        let header = NSButton(checkboxWithTitle: "First row is header", target: coordinator, action: #selector(Coordinator.toggleHeader))
        header.state = .on
        coordinator.headerCheckbox = header
        stack.addArrangedSubview(header)
        return stack
    }

    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: CSVEditor?
        var tableView: NSTableView?
        var headerCheckbox: NSButton?
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
        private var doc = CSVDocument()

        // MARK: - Wiring

        func loadFromText() {
            doc = CSVDocument.parse(parent?.text ?? "")
            headerCheckbox?.state = doc.hasHeader ? .on : .off
        }

        func serialize() -> String { doc.serialize() }

        func rebuildColumns() {
            guard let table = tableView else { return }
            table.tableColumns.forEach { table.removeTableColumn($0) }
            for (idx, header) in doc.headers.enumerated() {
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(idx)"))
                col.title = header
                col.width = columnWidths[idx] ?? 120
                col.minWidth = 60
                // Sort descriptor key encodes the column index — the
                // delegate's sortDescriptorsDidChange callback parses it
                // back to call CSVDocument.sort.
                col.sortDescriptorPrototype = NSSortDescriptor(key: "col\(idx)", ascending: true)
                table.addTableColumn(col)
            }
        }

        /// In-session column-width memo. Persists across reloadData /
        /// rebuildColumns within the same editor instance so the user's
        /// resize doesn't snap back when the doc reparses. Keyed by
        /// column index because the column identity itself is rebuilt.
        private var columnWidths: [Int: CGFloat] = [:]

        public func tableViewColumnDidResize(_ notification: Notification) {
            guard let col = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
                  let idx = tableView?.tableColumns.firstIndex(of: col) else { return }
            columnWidths[idx] = col.width
        }

        public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key,
                  key.hasPrefix("col"),
                  let columnIndex = Int(key.dropFirst(3)) else { return }
            performUndoable(actionName: "Sort by Column") {
                doc.sort(byColumn: columnIndex, ascending: descriptor.ascending)
            }
        }

        private func notifyChange() {
            parent?.text = doc.serialize()
        }

        /// Reload the table (optionally rebuilding the columns first) and
        /// echo the doc back to the binding. Every editing action funnels
        /// through here so the table view + binding stay in sync.
        private func applyChange(rebuildColumns rebuild: Bool = false) {
            if rebuild { rebuildColumns() }
            tableView?.reloadData()
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

        // MARK: - DataSource

        public func numberOfRows(in tableView: NSTableView) -> Int {
            return doc.bodyRows.count
        }

        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn else { return nil }
            let colIndex = tableView.tableColumns.firstIndex(of: column) ?? 0
            let rowIndex = doc.hasHeader ? row + 1 : row
            let value = doc.rows[safe: rowIndex]?[safe: colIndex] ?? ""

            let identifier = NSUserInterfaceItemIdentifier("cell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let tf = NSTextField(string: "")
                tf.isBordered = false
                tf.isEditable = true
                tf.drawsBackground = false
                tf.target = self
                tf.action = #selector(cellEdited(_:))
                cell.addSubview(tf)
                cell.textField = tf
                tf.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = value
            cell.textField?.tag = (rowIndex << 16) | colIndex
            return cell
        }

        // MARK: - Actions

        @objc func cellEdited(_ sender: NSTextField) {
            let packed = sender.tag
            let rowIndex = packed >> 16
            let colIndex = packed & 0xFFFF
            // Skip the snapshot if the value didn't actually change — typing
            // in and tabbing out of an unchanged cell shouldn't pollute the
            // undo stack.
            let oldValue = doc.rows[safe: rowIndex]?[safe: colIndex] ?? ""
            guard oldValue != sender.stringValue else { return }
            performUndoable(actionName: "Edit Cell") {
                doc.setCell(row: rowIndex, column: colIndex, to: sender.stringValue)
            }
        }

        @objc func addRow() {
            performUndoable(actionName: "Add Row") {
                doc.appendRow()
            }
        }

        /// Insert a blank row above the first selected row (header
        /// excluded — selection indices are body-relative). With no
        /// selection, falls back to appending at the end so the button
        /// is never a dead-end.
        @objc func insertRowBefore() {
            let selected = tableView?.selectedRowIndexes.first
            performUndoable(actionName: "Insert Row Before") {
                if let i = selected {
                    let docIndex = doc.hasHeader ? i + 1 : i
                    doc.insertRow(at: docIndex)
                } else {
                    doc.appendRow()
                }
            }
        }

        @objc func insertRowAfter() {
            let selected = tableView?.selectedRowIndexes.last
            performUndoable(actionName: "Insert Row After") {
                if let i = selected {
                    let docIndex = doc.hasHeader ? i + 2 : i + 1
                    doc.insertRow(at: docIndex)
                } else {
                    doc.appendRow()
                }
            }
        }

        @objc func insertColumnBefore() {
            let selected = tableView?.selectedColumnIndexes.first
            performUndoable(actionName: "Insert Column Before", rebuildColumns: true) {
                doc.insertColumn(at: selected ?? doc.columnCount)
                columnWidths.removeAll()   // indices shifted — stale widths
            }
        }

        @objc func insertColumnAfter() {
            let selected = tableView?.selectedColumnIndexes.last
            performUndoable(actionName: "Insert Column After", rebuildColumns: true) {
                doc.insertColumn(at: (selected ?? doc.columnCount - 1) + 1)
                columnWidths.removeAll()
            }
        }

        @objc func removeRow() {
            // Walk the multi-selection in descending order so removal indices
            // stay valid as rows shift up.
            guard let selected = tableView?.selectedRowIndexes, !selected.isEmpty else { return }
            performUndoable(actionName: selected.count > 1 ? "Delete Rows" : "Delete Row") {
                for i in selected.reversed() {
                    doc.removeRow(at: doc.hasHeader ? i + 1 : i)
                }
            }
        }

        @objc func addColumn() {
            performUndoable(actionName: "Add Column", rebuildColumns: true) {
                doc.appendColumn()
            }
        }

        @objc func removeColumn() {
            guard let selected = tableView?.selectedColumnIndexes, !selected.isEmpty else { return }
            performUndoable(actionName: selected.count > 1 ? "Delete Columns" : "Delete Column", rebuildColumns: true) {
                for i in selected.reversed() {
                    doc.removeColumn(at: i)
                }
                columnWidths.removeAll()   // indices shifted — stale widths
            }
        }

        /// Clear every cell in the row × column intersection of the
        /// current selection. Skips already-empty cells so an
        /// empty-on-empty Delete doesn't burn an undo entry.
        func clearSelectedCells() {
            guard let table = tableView else { return }
            // NSTableView row/column selection is mutually exclusive, so
            // CSVCellSelection treats whichever is active as the target:
            // selected columns clear top-to-bottom, selected rows clear
            // left-to-right. Pure resolver → header strip is never touched.
            let cells = CSVCellSelection.cellsToClear(
                selectedViewRows: table.selectedRowIndexes,
                selectedColumns: table.selectedColumnIndexes,
                bodyRowCount: doc.bodyRows.count,
                columnCount: doc.columnCount,
                hasHeader: doc.hasHeader
            )
            guard !cells.isEmpty else { return }
            performUndoable(actionName: cells.count > 1 ? "Clear Cells" : "Clear Cell") {
                _ = doc.clearCells(cells)
            }
        }

        /// `@objc` shim so the right-click menu can target the same
        /// clear-cells logic the Delete-key path uses.
        @objc func contextClearCells() { clearSelectedCells() }

        // MARK: - Copy / Cut / Paste (multi-cell blocks)

        /// Cells under the current selection, as document coordinates — the
        /// same resolver Delete uses, reused so copy/cut/clear all agree.
        private func selectedCells() -> [(row: Int, column: Int)] {
            guard let table = tableView else { return [] }
            return CSVCellSelection.cellsToClear(
                selectedViewRows: table.selectedRowIndexes,
                selectedColumns: table.selectedColumnIndexes,
                bodyRowCount: doc.bodyRows.count,
                columnCount: doc.columnCount,
                hasHeader: doc.hasHeader
            )
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
            let table = tableView
            let viewRow = table?.selectedRowIndexes.first ?? 0
            let anchorRow = doc.hasHeader ? viewRow + 1 : viewRow
            let anchorCol = table?.selectedColumnIndexes.first ?? 0
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
            guard let table = tableView else { return }
            table.selectRowIndexes(IndexSet(integer: match.row), byExtendingSelection: false)
            table.scrollRowToVisible(match.row)
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

        @objc func toggleHeader(_ sender: NSButton) {
            performUndoable(actionName: "Toggle Header", rebuildColumns: true) {
                doc.hasHeader = sender.state == .on
            }
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
            guard let undo = tableView?.window?.undoManager else { return }
            let coordinator = self
            undo.setActionName(actionName)
            undo.registerUndo(withTarget: self) { _ in
                let redoSnapshot = coordinator.doc.rows
                let redoHadHeader = coordinator.doc.hasHeader
                coordinator.doc.rows = snapshotRows
                coordinator.doc.hasHeader = hadHeader
                coordinator.headerCheckbox?.state = hadHeader ? .on : .off
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
