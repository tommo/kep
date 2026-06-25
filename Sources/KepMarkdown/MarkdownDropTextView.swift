import AppKit
import KepBase
import KepCore

/// NSTextView subclass that turns dropped files into the right markdown
/// snippet: images become `![alt](path)`, other text-like files become a
/// fenced code block. Falls back to the standard NSTextView behaviour for
/// anything else (plain text, rich text, attributed string drags).
public final class MarkdownDropTextView: NSTextView {

    /// Supplies the workspace document names offered when completing a `[[wiki
    /// link]]`. Set by `MarkdownEditor`; defaults to none so the view is inert
    /// when no knowledge-base context is wired up.
    public var wikiLinkCandidates: () -> [String] = { [] }

    /// ⌘-click on a `[[wiki link]]` opens its target. Set by `MarkdownEditor`.
    public var onOpenWikiLink: ((String, String?) -> Void)?

    /// ⌘-click follows a `[[wiki link]]` under the pointer; a plain click edits.
    public override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let open = onOpenWikiLink {
            let point = convert(event.locationInWindow, from: nil)
            let idx = characterIndexForInsertion(at: point)
            if let link = wikiLink(atCharIndex: idx) {
                open(link.target, link.heading)
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// The `[[target#heading]]` enclosing character index `i` on its line, if any.
    private func wikiLink(atCharIndex i: Int) -> (target: String, heading: String?)? {
        let ns = string as NSString
        guard i >= 0, i <= ns.length else { return nil }
        let line = ns.lineRange(for: NSRange(location: min(i, max(0, ns.length - 1)), length: 0))
        let lineText = ns.substring(with: line) as NSString
        let re = try! NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#)
        for m in re.matches(in: lineText as String, range: NSRange(location: 0, length: lineText.length)) {
            let abs = NSRange(location: line.location + m.range.location, length: m.range.length)
            guard i >= abs.location, i <= abs.location + abs.length else { continue }
            let inner = lineText.substring(with: m.range(at: 1))
            let parts = inner.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let target = String(parts[0])
            let heading = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
            return (target, heading)
        }
        return nil
    }

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

    // MARK: - Wiki-link completion

    /// The doc-name fragment + its range when the caret sits inside an open
    /// `[[`, else nil. Shared by `rangeForUserCompletion` (so multi-word names
    /// replace cleanly) and `completions(forPartialWordRange:)`.
    private func wikiPartial() -> (range: NSRange, text: String)? {
        let sel = selectedRange()
        guard sel.length == 0 else { return nil }
        let ns = string as NSString
        let caret = sel.location
        guard caret <= ns.length else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        let lineUpToCaret = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        guard let partial = WikiLinkCompletion.partial(inLineUpToCaret: lineUpToCaret) else { return nil }
        let len = (partial as NSString).length
        return (NSRange(location: caret - len, length: len), partial)
    }

    /// Inside `[[`, complete from the whole fragment after the brackets (so a
    /// name with spaces is replaced as a unit); otherwise the standard word range.
    public override var rangeForUserCompletion: NSRange {
        wikiPartial()?.range ?? super.rangeForUserCompletion
    }

    /// Offer matching workspace document names when completing a `[[wiki link]]`;
    /// otherwise defer to the system list.
    public override func completions(forPartialWordRange charRange: NSRange,
                                     indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard let wiki = wikiPartial() else {
            return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index)
        }
        let matches = WikiLinkCompletion.completions(forPartial: wiki.text, candidates: wikiLinkCandidates())
        return matches.isEmpty ? nil : matches
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

    /// Smart-delete the empty pair when backspacing inside one. After
    /// typing `(` and getting `()` with caret between, backspace removes
    /// both characters in one step instead of leaving an orphan `)`.
    /// Falls through to super for every other shape.
    public override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0, sel.location > 0 {
            let body = self.string as NSString
            if sel.location < body.length {
                let prevCh = body.substring(with: NSRange(location: sel.location - 1, length: 1))
                let nextCh = body.substring(with: NSRange(location: sel.location, length: 1))
                if let expectedCloser = MarkdownAutoPair.closer(for: prevCh),
                   String(expectedCloser) == nextCh {
                    let pairRange = NSRange(location: sel.location - 1, length: 2)
                    if shouldChangeText(in: pairRange, replacementString: "") {
                        replaceCharacters(in: pairRange, with: "")
                        didChangeText()
                    }
                    return
                }
            }
        }
        super.deleteBackward(sender)
    }

    /// Auto-pair openers — when the user types a bracket / quote / backtick
    /// against an empty selection, insert the matching closer and place
    /// the caret between them. Multi-char inserts (IME composition,
    /// pasted runs) and non-opener chars fall through unchanged.
    public override func insertText(_ string: Any, replacementRange: NSRange) {
        // Step-over: typing a closer that's already at the caret advances
        // past it instead of inserting a duplicate. Pairs with #126's
        // auto-pair so `()` + typing `)` inside leaves cursor *after* the
        // existing `)`. Mirror pairs (`"`, `'`) are excluded — the same
        // char is opener and closer so stepping past would prevent
        // typing the quoted body.
        if let str = string as? String,
           replacementRange.length == 0,
           selectedRange().length == 0,
           MarkdownAutoPair.isSteppableCloser(str) {
            let body = self.string as NSString
            let caret = selectedRange().location
            if caret < body.length,
               body.substring(with: NSRange(location: caret, length: 1)) == str {
                setSelectedRange(NSRange(location: caret + 1, length: 0))
                return
            }
        }
        if let str = string as? String,
           replacementRange.length == 0,
           let closer = MarkdownAutoPair.closer(for: str) {
            let target = selectedRange()
            if target.length == 0 {
                // Empty selection — auto-pair: insert opener+closer, caret
                // lands between them.
                let pair = "\(str)\(closer)"
                if shouldChangeText(in: target, replacementString: pair) {
                    replaceCharacters(in: target, with: pair)
                    didChangeText()
                    setSelectedRange(NSRange(location: target.location + 1, length: 0))
                }
                return
            } else {
                // Non-empty selection — wrap: opener + selection + closer.
                // Inner text stays re-selected so the user can keep typing
                // wrappers around it or replace it. Matches Sublime / VS
                // Code's default behavior.
                let selectedText = (self.string as NSString).substring(with: target)
                let wrapped = "\(str)\(selectedText)\(closer)"
                if shouldChangeText(in: target, replacementString: wrapped) {
                    replaceCharacters(in: target, with: wrapped)
                    didChangeText()
                    // Re-select the inner text (unchanged) so the user can
                    // keep typing wrappers around it or replace it.
                    setSelectedRange(NSRange(location: target.location + 1, length: target.length))
                }
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Smart paste — handles two convention overrides before falling
    /// through to standard text paste:
    ///   1. Selection + URL on pasteboard → wrap as `[selected](URL)`.
    ///   2. Image on pasteboard → insert `![pasted](data:image/png;base64,…)`
    ///      so the casual screenshot-into-doc case doesn't need a sidecar
    ///      file write. Sibling to #70 (drop image file → ![](path)).
    public override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let selection = selectedRange()
        if selection.length > 0,
           let url = MarkdownPasteRule.urlFromPasteboard(pb) {
            let body = string as NSString
            let selectedText = body.substring(with: selection)
            let replacement = "[\(selectedText)](\(url))"
            if shouldChangeText(in: selection, replacementString: replacement) {
                replaceCharacters(in: selection, with: replacement)
                didChangeText()
                setSelectedRange(NSRange(location: selection.location + (replacement as NSString).length, length: 0))
            }
            return
        }
        if let base64 = Self.imageBase64(from: pb) {
            let snippet = "![pasted](data:image/png;base64,\(base64))"
            if shouldChangeText(in: selection, replacementString: snippet) {
                replaceCharacters(in: selection, with: snippet)
                didChangeText()
                setSelectedRange(NSRange(location: selection.location + (snippet as NSString).length, length: 0))
            }
            return
        }
        super.paste(sender)
    }

    /// Read PNG bytes from the pasteboard (direct .png type, falling back
    /// to NSImage decode + PNG re-encode for TIFF/JPEG/PDF) and return
    static func imageBase64(from pasteboard: NSPasteboard) -> String? {
        PasteboardImage.base64(from: pasteboard)
    }

    /// ⌘B / ⌘I / ⌘E / ⌘K → bold / italic / inline-code / link. Shortcuts
    /// route through the delegate (the SwiftUI Coordinator) which already
    /// has @objc handlers wired to MarkdownFormatting.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only claim ⌘B/I/E/K when WE are the focused editor. performKeyEquivalent
        // propagates through the whole window view tree, so without this an
        // inspector note editor would bold/italicise its text even when the
        // mind-map canvas (not this view) holds focus — ⌘B on a selected node
        // leaked into its note.
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let chars = event.charactersIgnoringModifiers ?? ""
        let onlyCommand = event.modifierFlags
            .intersection([.command, .option, .control, .shift]) == [.command]
        if onlyCommand, let action = Self.formattingShortcuts[chars] {
            if let target = delegate, target.responds(to: action) {
                _ = target.perform(action)
                return true
            }
        }
        // ⌥⌘1/2/3 → Heading 1/2/3 (number shortcuts; option-modified to avoid
        // clashing with ⌘1.. tab/zoom bindings).
        let commandOption = event.modifierFlags
            .intersection([.command, .option, .control, .shift]) == [.command, .option]
        if commandOption, let action = Self.headingShortcuts[chars] {
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

    /// ⌥⌘<n> → Heading <n>. Separate map since these fire only with the
    /// command+option combo (see performKeyEquivalent).
    static let headingShortcuts: [String: Selector] = [
        "1": Selector(("toolbarHeading1")),
        "2": Selector(("toolbarHeading2")),
        "3": Selector(("toolbarHeading3")),
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

    public static func snippet(for urls: [URL], relativeToFileAt docURL: URL? = nil) -> String {
        var parts: [String] = []
        for url in urls {
            if let s = snippet(for: url, relativeToFileAt: docURL) { parts.append(s) }
        }
        return parts.joined(separator: "\n\n")
    }

    public static func snippet(for url: URL, relativeToFileAt docURL: URL? = nil) -> String? {
        let ext = url.pathExtension.lowercased()
        // Relative to the document's folder when known (so the link survives the
        // workspace moving); absolute otherwise.
        let path = docURL.map { RelativePath.from(fileAt: $0, to: url) } ?? url.path
        if imageExtensions.contains(ext) {
            let alt = url.deletingPathExtension().lastPathComponent
            return "![\(escapeAlt(alt))](\(escapeURL(path)))"
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
