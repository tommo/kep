import AppKit

/// NSTextView subclass that turns dropped files into the right markdown
/// snippet: images become `![alt](path)`, other text-like files become a
/// fenced code block. Falls back to the standard NSTextView behaviour for
/// anything else (plain text, rich text, attributed string drags).
public final class MarkdownDropTextView: NSTextView {

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        registerForDraggedTypes([.fileURL])
    }

    /// Override Enter to auto-continue lists. When the current line starts
    /// with a markdown list marker (`-`, `*`, `+`, `1.`), the next line
    /// gets the same marker prepended (numeric markers increment). When
    /// the source line is just-a-marker (no body text), Enter strips the
    /// marker instead — that's how the user breaks out of a list.
    public override func insertNewline(_ sender: Any?) {
        let body = string as NSString
        let caret = selectedRange().location
        let lineRange = body.lineRange(for: NSRange(location: caret, length: 0))
        let line = body.substring(with: NSRange(location: lineRange.location,
                                                length: caret - lineRange.location))
        guard let action = MarkdownListContinuation.action(for: line) else {
            // No list marker on this line — preserve leading indentation
            // (spaces or tabs) on the next line so wrapped paragraphs and
            // code-style indented prose stay aligned. Empty leading indent
            // falls through to plain super.insertNewline.
            let leading = MarkdownListContinuation.leadingIndent(of: line)
            if !leading.isEmpty {
                let inserted = "\n" + leading
                if shouldChangeText(in: selectedRange(), replacementString: inserted) {
                    replaceCharacters(in: selectedRange(), with: inserted)
                    didChangeText()
                }
            } else {
                super.insertNewline(sender)
            }
            return
        }
        switch action {
        case .insert(let prefix):
            let inserted = "\n" + prefix
            if shouldChangeText(in: selectedRange(), replacementString: inserted) {
                replaceCharacters(in: selectedRange(), with: inserted)
                didChangeText()
            }
        case .clearMarker:
            // Replace the entire current line (just the marker) with empty,
            // so Enter ends up as a fresh blank line — drops the user out
            // of the list.
            let lineToCaret = NSRange(location: lineRange.location,
                                      length: caret - lineRange.location)
            if shouldChangeText(in: lineToCaret, replacementString: "") {
                replaceCharacters(in: lineToCaret, with: "")
                didChangeText()
            }
        }
    }

    /// ⌘B / ⌘I / ⌘E / ⌘K → bold / italic / inline-code / link. Shortcuts
    /// route through the delegate (the SwiftUI Coordinator) which already
    /// has @objc handlers wired to MarkdownFormatting.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        let onlyCommand = event.modifierFlags
            .intersection([.command, .option, .control, .shift]) == [.command]
        if onlyCommand, let action = Self.formattingShortcuts[chars] {
            if let target = delegate, target.responds(to: action) {
                _ = target.perform(action)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Map of single ASCII chars (cmd-modified) → Coordinator selector.
    /// Exposed for unit tests.
    static let formattingShortcuts: [String: Selector] = [
        "b": Selector(("toolbarBold")),
        "i": Selector(("toolbarItalic")),
        "e": Selector(("toolbarInlineCode")),
        "k": Selector(("toolbarLink")),
    ]

    /// Tab indents the line(s) covered by the current selection — one
    /// "  " (2-space) level per press. Multi-line selections get every
    /// line indented in a single undoable step. Caret stays inside the
    /// modified block by extending the resulting selection range.
    public override func insertTab(_ sender: Any?) {
        applyLineTransform(MarkdownIndent.indent)
    }

    /// Shift-Tab outdents — removes one "  " or one leading "\t" from
    /// each covered line. Lines without indent stay as-is.
    public override func insertBacktab(_ sender: Any?) {
        applyLineTransform(MarkdownIndent.outdent)
    }

    /// Shared scaffolding for the two indent overrides — expand the
    /// selection to whole lines, run `transform` over the block, and
    /// commit through shouldChangeText / replaceCharacters / didChangeText
    /// so the edit lands on the undo stack as one entry.
    private func applyLineTransform(_ transform: (String) -> String) {
        let body = string as NSString
        let selection = selectedRange()
        let lineRange = body.lineRange(for: selection)
        // Don't pull in the trailing newline — keeps the transform
        // operating on visible-line content only.
        var workRange = lineRange
        if workRange.length > 0,
           body.character(at: workRange.location + workRange.length - 1) == 0x0A /* \n */ {
            workRange.length -= 1
        }
        let block = body.substring(with: workRange)
        let replaced = transform(block)
        guard replaced != block, shouldChangeText(in: workRange, replacementString: replaced) else { return }
        replaceCharacters(in: workRange, with: replaced)
        didChangeText()
        // Re-select the modified region so subsequent Tab presses keep
        // operating on the same block.
        setSelectedRange(NSRange(location: workRange.location, length: (replaced as NSString).length))
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else {
            return super.performDragOperation(sender)
        }
        let snippet = MarkdownDropFormatter.snippet(for: urls)
        guard !snippet.isEmpty else { return super.performDragOperation(sender) }
        // Insert at the existing caret / selection — replaceCharacters routes
        // through the responder chain so it remains undoable.
        let range = selectedRange()
        if shouldChangeText(in: range, replacementString: snippet) {
            replaceCharacters(in: range, with: snippet)
            didChangeText()
            // Move the caret to the end of the inserted snippet.
            setSelectedRange(NSRange(location: range.location + (snippet as NSString).length, length: 0))
        }
        return true
    }
}

/// Pure-logic builder for the markdown snippet that a dropped file becomes.
/// Lives outside the NSTextView so the rules can be unit-tested without an
/// AppKit drag-pasteboard fixture.
public enum MarkdownDropFormatter {
    /// Image extensions Mindolph treats as inline images.
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "heic", "heif"]
    /// Text-like extensions worth inlining as a fenced code block. Pulled
    /// from Mindolph's `EditorView` drop handler.
    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "swift", "java", "kt", "py", "rb", "go", "rs",
        "c", "h", "cpp", "hpp", "m", "mm", "js", "ts", "jsx", "tsx",
        "json", "yaml", "yml", "toml", "xml", "html", "css", "sh", "bash", "zsh",
        "sql", "log", "cfg", "ini", "csv"
    ]

    public static func snippet(for urls: [URL]) -> String {
        var parts: [String] = []
        for url in urls {
            if let s = snippet(for: url) { parts.append(s) }
        }
        return parts.joined(separator: "\n\n")
    }

    public static func snippet(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) {
            let alt = url.deletingPathExtension().lastPathComponent
            return "![\(escapeAlt(alt))](\(escapeURL(url.path)))"
        }
        if textExtensions.contains(ext) {
            // Inline the contents as a fenced code block. Skip silently on
            // read failure — the user can drag a different file.
            guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let lang = ext == "md" || ext == "markdown" ? "" : ext
            let trimmed = body.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return "```\(lang)\n\(trimmed)\n```"
        }
        return nil
    }

    /// Escape `]` and `[` in alt text so the markdown link doesn't break.
    static func escapeAlt(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    /// URL-encode the path so spaces and parens don't break the link.
    /// Markdown only requires escaping `(`, `)`, and whitespace inside the URL.
    static func escapeURL(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }
}
