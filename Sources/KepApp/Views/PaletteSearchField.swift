import SwiftUI
import AppKit

/// AppKit-backed search field for the palettes. SwiftUI's `TextField` inside a
/// `.sheet` on macOS is flaky about focus and about propagating edits to its
/// binding; an `NSSearchField` whose delegate writes the binding on
/// `controlTextDidChange` is the documented, reliable approach. Arrow / Return /
/// Esc are routed out via `doCommandBy` so the list can drive selection.
struct PaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.font = .systemFont(ofSize: 16)
        (field.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        field.translatesAutoresizingMaskIntoConstraints = false
        // Grab focus once the field is in a window.
        DispatchQueue.main.async { [weak field] in
            field?.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: PaletteSearchField
        init(_ parent: PaletteSearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):       parent.onMoveUp();   return true
            case #selector(NSResponder.moveDown(_:)):     parent.onMoveDown(); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit();  return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            default: return false
            }
        }
    }
}
