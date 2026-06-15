import AppKit

/// Content for the note hover popover: the node's note rendered as Markdown.
/// Uses Foundation's built-in Markdown→AttributedString so bold / italic /
/// code / links render without pulling in the full editor stack. Sized
/// explicitly from the text's bounding rect (autolayout fittingSize inside a
/// popover was unreliable and produced an empty box).
final class NoteHoverController: NSViewController {
    private let markdown: String

    init(markdown: String) {
        self.markdown = markdown
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let textWidth: CGFloat = 300
    private static let hPad: CGFloat = 10
    private static let vPad: CGFloat = 8

    override func loadView() {
        let attr = Self.render(markdown)
        let bounding = attr.boundingRect(
            with: NSSize(width: Self.textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        let w = max(ceil(bounding.width), 40)
        let h = max(ceil(bounding.height), 16)

        let label = NSTextField(labelWithAttributedString: attr)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = Self.textWidth
        label.frame = NSRect(x: Self.hPad, y: Self.vPad, width: w, height: h)

        let container = NSView(frame: NSRect(x: 0, y: 0,
                                             width: w + Self.hPad * 2,
                                             height: h + Self.vPad * 2))
        container.addSubview(label)
        view = container
        preferredContentSize = container.frame.size
    }

    /// Render markdown to an attributed string, preserving line breaks (a note
    /// is usually multi-line prose, not a single paragraph). Forces a concrete
    /// base font + label color wherever markdown left them unset, so the text
    /// is actually visible. Falls back to the raw text if parsing fails.
    private static func render(_ source: String) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: 12)
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: source, options: options) else {
            return NSAttributedString(string: source,
                                      attributes: [.font: base, .foregroundColor: NSColor.labelColor])
        }
        let ns = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
        let full = NSRange(location: 0, length: ns.length)
        ns.enumerateAttribute(.font, in: full) { value, range, _ in
            if value == nil { ns.addAttribute(.font, value: base, range: range) }
        }
        ns.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if value == nil { ns.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
        }
        return ns
    }
}
