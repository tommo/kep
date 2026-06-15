import AppKit

/// Content for the note hover popover: the node's note rendered as Markdown.
/// Uses Foundation's built-in Markdown→AttributedString so bold / italic /
/// code / links render without pulling in the full editor stack. Sized to its
/// content (capped width) so the popover hugs the text.
final class NoteHoverController: NSViewController {
    private let markdown: String

    init(markdown: String) {
        self.markdown = markdown
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let maxWidth: CGFloat = 320

    override func loadView() {
        let label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = Self.render(markdown)
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.preferredMaxLayoutWidth = Self.maxWidth - 20

        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxWidth - 20),
        ])
        view = container
    }

    /// Render markdown to an attributed string, preserving line breaks (a note
    /// is usually multi-line prose, not a single paragraph). Falls back to the
    /// raw text if parsing fails.
    private static func render(_ source: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: source, options: options) {
            let ns = NSMutableAttributedString(attributed)
            // Ensure a concrete base font where markdown left none, without
            // clobbering the bold / italic / code fonts it did apply.
            let base = NSFont.systemFont(ofSize: 12)
            ns.enumerateAttribute(.font, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
                if value == nil { ns.addAttribute(.font, value: base, range: range) }
            }
            return ns
        }
        return NSAttributedString(string: source,
                                  attributes: [.font: NSFont.systemFont(ofSize: 12)])
    }
}
