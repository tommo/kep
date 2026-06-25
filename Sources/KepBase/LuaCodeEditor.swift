import SwiftUI
import AppKit

/// Reusable editable, Lua-syntax-highlighted text editor (CodeArea + the shared
/// LuaHighlighter). Used by the CSV Sheet Blocks panel and the `.lua` document
/// editor so every Lua surface highlights consistently.
public struct LuaCodeEditor: NSViewRepresentable {
    @Binding public var text: String
    public var isDark: Bool

    public init(text: Binding<String>, isDark: Bool) {
        self._text = text
        self.isDark = isDark
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = CodeArea.makeMonospaced(text: text, delegate: context.coordinator)
        tv.allowsUndo = true
        context.coordinator.textView = tv
        context.coordinator.dark = isDark
        context.coordinator.highlight(tv)
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
            context.coordinator.highlight(tv)
        } else if context.coordinator.dark != isDark {
            context.coordinator.dark = isDark
            context.coordinator.highlight(tv)
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        weak var textView: NSTextView?
        var dark = false
        init(text: Binding<String>) { self.text = text }

        public func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, tv.string != text.wrappedValue else { return }
            text.wrappedValue = tv.string
            highlight(tv)
        }

        func highlight(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            LuaHighlighter.apply(to: storage, dark: dark,
                                 font: tv.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular))
        }
    }
}
