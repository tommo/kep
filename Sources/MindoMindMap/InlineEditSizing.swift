import AppKit

/// Pure sizing for the inline editor so the field grows to fit the text as the
/// user types (mirrors `MindMapLayout`'s topic measurement). Kept out of the
/// view so the rule is unit-testable.
enum InlineEditSizing {
    /// Fitting size for `text` in `font` with the theme's text insets, wrapping
    /// at `maxWidth`. `bezelSlack` accounts for the rounded-bezel chrome so the
    /// caret/last glyph isn't clipped. Clamped to sensible minimums.
    static func fittingSize(
        text: String,
        font: NSFont,
        insets: NSEdgeInsets,
        maxWidth: CGFloat = 320,
        bezelSlack: CGFloat = 12,
        minSize: CGSize = CGSize(width: 40, height: 28)
    ) -> CGSize {
        let measured = (text.isEmpty ? " " : text) as NSString
        let bounding = measured.boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        let w = ceil(bounding.width) + insets.left + insets.right + bezelSlack
        let h = ceil(bounding.height) + insets.top + insets.bottom
        return CGSize(width: max(minSize.width, w), height: max(minSize.height, h))
    }
}
