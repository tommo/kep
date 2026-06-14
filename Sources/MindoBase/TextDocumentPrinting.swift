import AppKit

/// Helper for printing the focused text/web document via the responder
/// chain.
///
/// The old ⌘P path sent the `printDocument:` selector — but that's an
/// `NSDocument` method, and this app is not document-based. The actual
/// first responders (NSTextView for the source editors, WKWebView for the
/// previews) are `NSView`s, which respond to `print:`, NOT `printDocument:`.
/// So the action found no handler in the chain and printing silently did
/// nothing. Sending `print:` is the fix.
public enum TextDocumentPrinting {

    /// The selector NSView-based responders implement for printing.
    public static let printSelector = Selector(("print:"))

    /// Ask the first responder (focused text view / web view) to print
    /// itself. Returns whether a responder in the chain accepted the action.
    @discardableResult
    public static func printFirstResponder() -> Bool {
        NSApp.sendAction(printSelector, to: nil, from: nil)
    }
}
