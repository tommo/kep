import AppKit
import MindoCore

/// Builders for the bare NSScrollView + NSTextView pair shared by the
/// markdown / plantuml code editors. Callers tack on per-editor settings
/// (autoresizing, container size, font panel, etc.) after the call.
public enum CodeArea {

    /// Vertically-scrollable monospaced NSTextView wrapped in an NSScrollView.
    /// Sets the common defaults: monospaced font (size from
    /// PrefKeys.editorFontSize, default 13pt), undo, find bar, resizable
    /// height, width tracking. Returns both views so the caller can install
    /// them and add per-editor configuration.
    public static func makeMonospaced(
        text: String,
        delegate: NSTextViewDelegate? = nil
    ) -> (scroll: NSScrollView, textView: NSTextView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        let fontSize = CGFloat(PrefKeys.double(PrefKeys.editorFontSize, fallback: 13))
        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.string = text
        textView.delegate = delegate
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        scroll.documentView = textView
        return (scroll, textView)
    }
}
