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
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        scroll.documentView = table

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        context.coordinator.tableView = table
        context.coordinator.parent = self
        context.coordinator.loadFromText()
        context.coordinator.rebuildColumns()
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
            doc.sort(byColumn: columnIndex, ascending: descriptor.ascending)
            applyChange()
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
            doc.setCell(row: rowIndex, column: colIndex, to: sender.stringValue)
            notifyChange()
        }

        @objc func addRow() {
            doc.appendRow()
            applyChange()
        }

        @objc func removeRow() {
            guard let selected = tableView?.selectedRow, selected >= 0 else { return }
            doc.removeRow(at: doc.hasHeader ? selected + 1 : selected)
            applyChange()
        }

        @objc func addColumn() {
            doc.appendColumn()
            applyChange(rebuildColumns: true)
        }

        @objc func removeColumn() {
            guard let selected = tableView?.selectedColumn, selected >= 0 else { return }
            doc.removeColumn(at: selected)
            applyChange(rebuildColumns: true)
        }

        @objc func toggleHeader(_ sender: NSButton) {
            doc.hasHeader = sender.state == .on
            applyChange(rebuildColumns: true)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        return (index >= 0 && index < count) ? self[index] : nil
    }
}
