import AppKit
import MindoBase

/// NSTextView subclass for the PlantUML editor — adds Tab/Shift-Tab
/// indent/outdent on the line-block under the current selection,
/// mirroring the behavior shipped for the markdown editor.
public final class PlantUMLTextView: NSTextView {

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Autocomplete PlantUML keywords / skinparam names (⌥Esc, or the standard
    /// completion key). Falls back to the system list when we have nothing.
    public override func completions(forPartialWordRange charRange: NSRange,
                                     indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String]? {
        let ns = string as NSString
        guard charRange.location != NSNotFound,
              NSMaxRange(charRange) <= ns.length else { return nil }
        let partial = ns.substring(with: charRange)
        // The text from the line start up to the partial word, for context
        // (e.g. detecting a `skinparam ` line).
        let lineStart = ns.lineRange(for: NSRange(location: charRange.location, length: 0)).location
        let lineUpToCaret = ns.substring(with: NSRange(location: lineStart,
                                                       length: charRange.location - lineStart))
        let matches = PlantUMLCompletion.completions(forPartialWord: partial, lineUpToCaret: lineUpToCaret)
        return matches.isEmpty ? nil : matches
    }

    public override func insertTab(_ sender: Any?) {
        applyLineTransform(EditorIndent.indent)
    }

    public override func insertBacktab(_ sender: Any?) {
        applyLineTransform(EditorIndent.outdent)
    }

    /// Toggle `' ` line comments on the line block under the selection.
    /// Mirrors what the toolbar Comment button does so ⌘/ and the
    /// button stay in sync.
    @objc public func toggleLineComment() {
        applyLineTransform(PlantUMLCommentToggle.toggle)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift),
           !event.modifierFlags.contains(.option),
           event.charactersIgnoringModifiers == "/" {
            toggleLineComment()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Same scaffolding as the markdown editor's — expand the selection
    /// to whole lines, run `transform` over the block, commit through
    /// shouldChangeText / didChangeText so the edit lands as one undo
    /// entry. Re-selects the modified region so Tab presses keep stacking.
    private func applyLineTransform(_ transform: (String) -> String) {
        let body = string as NSString
        let selection = selectedRange()
        let lineRange = body.lineRange(for: selection)
        var workRange = lineRange
        if workRange.length > 0,
           body.character(at: workRange.location + workRange.length - 1) == 0x0A {
            workRange.length -= 1
        }
        let block = body.substring(with: workRange)
        let replaced = transform(block)
        guard replaced != block, shouldChangeText(in: workRange, replacementString: replaced) else { return }
        replaceCharacters(in: workRange, with: replaced)
        didChangeText()
        setSelectedRange(NSRange(location: workRange.location, length: (replaced as NSString).length))
    }
}
