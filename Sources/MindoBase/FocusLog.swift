import AppKit

/// Lightweight focus diagnostics. Prints the window's current first responder at
/// instrumented sites so we can see exactly who grabs keyboard focus. Lines are
/// prefixed `[FOCUS]` for easy grepping. Toggle with `MINDO_FOCUS_LOG=0`.
/// TEMPORARY — remove once the focus-bounce is pinned down.
public enum FocusLog {
    public static var enabled = ProcessInfo.processInfo.environment["MINDO_FOCUS_LOG"] != "0"

    /// Describe the current first responder of the key/main window.
    public static func responder() -> String {
        let w = NSApp.keyWindow ?? NSApp.mainWindow
        guard let fr = w?.firstResponder else { return "nil" }
        if let v = fr as? NSView {
            // Walk a couple of superviews for context (e.g. an NSTextView inside
            // a field editor inside the sidebar vs the canvas).
            return "\(type(of: v))"
        }
        return "\(type(of: fr))"
    }

    public static func log(_ tag: String) {
        guard enabled else { return }
        print("[FOCUS] \(tag) | firstResponder=\(responder())")
    }
}
