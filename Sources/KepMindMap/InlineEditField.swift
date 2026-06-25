import AppKit

/// Tiny NSTextField subclass that surfaces Esc as a callback so the
/// MindMapView can discard an in-flight inline edit. NSTextField's
/// default `cancelOperation(_:)` is a no-op; without this the user
/// would type, hit Esc, and find the editor still hovering on the
/// canvas with their (unsaved) text intact.
final class InlineEditField: NSTextField {
    /// Called when Esc is pressed inside the field — typically wired by
    /// `MindMapView.beginInlineEdit` to call `cancelInlineEdit()`.
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
