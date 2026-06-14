import AppKit

/// NSTableView subclass that forwards Delete / Backspace to a closure
/// when there's a row + column selection but no cell is being edited.
/// Without this, those keys do nothing in NSTableView's default
/// responder chain — Excel / mindolph users expect Delete to clear
/// the cells under selection.
public final class CSVTableView: NSTableView {

    /// Called on Delete or Backspace when no editor session is active
    /// and at least one row + column is selected. Caller resolves the
    /// selection, runs the clear through its undo stack, and reloads.
    public var onClearSelectedCells: (() -> Void)?

    public override func keyDown(with event: NSEvent) {
        // Already-editing cells route deleteForward / deleteBackward
        // straight to the field editor, so we only catch the keys when
        // no editor is up. NSTableView publishes the editing row via
        // editedRow/editedColumn — both -1 when nothing's being edited.
        // Fire when EITHER rows or columns are selected — NSTableView makes
        // the two mutually exclusive, so requiring both (as before) meant
        // Delete could never fire at all. The coordinator's resolver maps a
        // whole-row or whole-column selection to the cells to clear.
        let editing = editedRow != -1 || editedColumn != -1
        if !editing,
           !(selectedRowIndexes.isEmpty && selectedColumnIndexes.isEmpty),
           let chars = event.charactersIgnoringModifiers,
           let scalar = chars.unicodeScalars.first,
           scalar == "\u{7F}" || scalar == "\u{08}" {  // Delete (forward) or Backspace
            onClearSelectedCells?()
            return
        }
        super.keyDown(with: event)
    }
}
