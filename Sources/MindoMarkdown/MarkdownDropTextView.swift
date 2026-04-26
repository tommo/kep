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
            super.insertNewline(sender)
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
