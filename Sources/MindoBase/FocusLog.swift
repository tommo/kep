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

    /// Fixed log file so the app can be launched any way (even double-clicked
    /// from Finder, where stdout is discarded) and still record focus events.
    private static let logURL = URL(fileURLWithPath: "/tmp/mindo-focus.log")
    private static var didStart = false

    public static func log(_ tag: String) {
        guard enabled else { return }
        let line = "[FOCUS] \(tag) | firstResponder=\(responder())\n"
        print(line, terminator: "")
        append(line)
    }

    private static func append(_ line: String) {
        if !didStart {   // truncate at first write each launch so the file is one session
            didStart = true
            try? "[FOCUS] --- session start ---\n".write(to: logURL, atomically: false, encoding: .utf8)
        }
        guard let data = line.data(using: .utf8),
              let h = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? h.close() }
        h.seekToEndOfFile()
        h.write(data)
    }
}
