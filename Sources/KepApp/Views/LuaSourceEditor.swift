import SwiftUI
import AppKit
import KepBase

/// Editable, Lua-syntax-highlighted document editor for `.lua` files (notebook
/// libraries: `notebook.lua`, `lib/*.lua`). Reuses the shared monospaced code
/// area + `LuaHighlighter` (same highlighting as notebook code cells). Edits to
/// libraries take effect in a notebook on its next Run All (kernel rebuild).
struct LuaSourceEditor: NSViewRepresentable {
    @Binding var text: String
    var isDark: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = CodeArea.makeMonospaced(text: text, delegate: context.coordinator)
        tv.allowsUndo = true
        context.coordinator.textView = tv
        context.coordinator.dark = isDark
        context.coordinator.highlight(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
            context.coordinator.highlight(tv)
        } else if context.coordinator.dark != isDark {
            context.coordinator.dark = isDark
            context.coordinator.highlight(tv)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        weak var textView: NSTextView?
        var dark = false
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
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
