import AppKit
import SwiftUI

/// Visual table editor for CSV documents. Wraps an `NSTableView` so we get
/// native cell editing, keyboard navigation, and selection. Toolbar above the
/// table exposes add/remove row/column.
public struct CSVEditor: NSViewRepresentable {
    @Binding public var text: String

    public init(text: Binding<String>) {
        self._text = text
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let toolbar = makeToolbar(coordinator: context.coordinator)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .lineBorder
        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        table.allowsColumnResizing = true
        table.allowsColumnReordering = false
        table.allowsMultipleSelection = true
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        scroll.documentView = table

        // Status footer — rows × cols, mirrors the markdown / plantuml /
        // mindmap editor footers.
        let footer = NSTextField(labelWithString: "")
        footer.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        footer.textColor = .secondaryLabelColor
        footer.alignment = .right
        footer.translatesAutoresizingMaskIntoConstraints = false

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)
        container.addSubview(scroll)
        container.addSubview(footer)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
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
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    private func makeToolbar(coordinator: Coordinator) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        func button(_ title: String, _ tooltip: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: coordinator, action: action)
            b.bezelStyle = .rounded
            b.toolTip = tooltip
            return b
        }

        stack.addArrangedSubview(button("+ Row", "Append a new row", #selector(Coordinator.addRow)))
        stack.addArrangedSubview(button("− Row", "Remove the selected row", #selector(Coordinator.removeRow)))
        stack.addArrangedSubview(button("+ Column", "Append a new column", #selector(Coordinator.addColumn)))
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
            }
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
