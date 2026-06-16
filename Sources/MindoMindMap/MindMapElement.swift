import AppKit
import Foundation
import MindoModel

/// Visual element that wraps a `Topic` for layout & rendering. Mirrors `BaseElement`
/// from `mindmap-panel`, simplified to one type with a `level` discriminator.
public final class MindMapElement {
    public let topic: Topic
    public let level: Int
    /// Children, in tree order. For the root, these split between `leftChildren` and `rightChildren`.
    public internal(set) var children: [MindMapElement] = []
    /// At root only — the left-side subset of children.
    public internal(set) var leftChildren: [MindMapElement] = []
    public internal(set) var rightChildren: [MindMapElement] = []

    /// `true` when this topic lives on the left half of the root.
    public internal(set) var isLeftSide: Bool = false

    /// The element's own rectangle (text bounds), in canvas coordinates.
    public internal(set) var frame: CGRect = .zero

    /// The size of just this element (text + insets), independent of children.
    public internal(set) var elementSize: CGSize = .zero

    /// Bounds of the entire subtree rooted at this element.
    public internal(set) var subtreeBounds: CGRect = .zero

    /// Manual layout nudge from the `offsetX`/`offsetY` topic attributes,
    /// applied on top of the auto-layout position. `.zero` when unset.
    public var manualOffset: CGPoint {
        let x = topic.attribute(TopicAttribute.offsetX).flatMap(Double.init) ?? 0
        let y = topic.attribute(TopicAttribute.offsetY).flatMap(Double.init) ?? 0
        return CGPoint(x: x, y: y)
    }

    public init(topic: Topic, level: Int) {
        self.topic = topic
        self.level = level
    }

    /// Build an element tree from a topic tree.
    public static func build(from topic: Topic, level: Int = 0) -> MindMapElement {
        let element = MindMapElement(topic: topic, level: level)
        for child in topic.children {
            element.children.append(MindMapElement.build(from: child, level: level + 1))
        }
        return element
    }

    /// Pre-order traversal across the whole element tree.
    public func traverse(_ visit: (MindMapElement) -> Void) {
        visit(self)
        for c in children { c.traverse(visit) }
    }

    /// True if this topic's `collapsed` attribute is set.
    public var isCollapsed: Bool {
        topic.attribute(TopicAttribute.collapsed).flatMap(Bool.init) ?? false
    }

    /// Effective children for layout — empty when collapsed.
    public var visibleChildren: [MindMapElement] {
        isCollapsed ? [] : children
    }

    /// Clickable fold/unfold target ("collapsator") for any non-root topic
    /// that has children — a small circle just outside the edge facing the
    /// children (right edge for right-side / root-right nodes, left edge for
    /// left-side ones). nil for leaves and the root. Same coordinate space as
    /// `frame`. Drives both the drawn indicator and its mouse hit-test, so the
    /// two can never drift apart.
    public var collapseIndicatorRect: CGRect? {
        guard !children.isEmpty, topic.parent != nil else { return nil }
        let d = Self.collapseIndicatorSize
        let x = isLeftSide ? frame.minX - d - Self.collapseIndicatorGap
                           : frame.maxX + Self.collapseIndicatorGap
        return CGRect(x: x, y: frame.midY - d / 2, width: d, height: d)
    }

    public static let collapseIndicatorSize: CGFloat = 14
    public static let collapseIndicatorGap: CGFloat = 3

    // MARK: - Extras strip

    /// Ordered list of extras present on this topic, in the order we render
    /// them as icons (note, link, file, topic).
    public var visibleExtras: [ExtraType] {
        let order: [ExtraType] = [.note, .link, .file, .topic]
        return order.filter { topic.extra($0) != nil }
    }

    /// Total width reserved for the icon strip on this element. The layout
    /// caches it so `MindMapLayout` can grow the element width to fit.
    public var extraIconStripWidth: CGFloat {
        let count = visibleExtras.count
        if count == 0 { return 0 }
        return CGFloat(count) * (extraIconSize + extraIconGap) + extraIconLeading
    }

    /// Per-icon hit rects, in the same coordinate space as `frame`.
    public var extraIconRects: [(ExtraType, CGRect)] {
        let extras = visibleExtras
        guard !extras.isEmpty else { return [] }
        let stripWidth = extraIconStripWidth
        let stripStartX = frame.maxX - stripWidth + extraIconLeading
        let y = frame.midY - extraIconSize / 2
        var rects: [(ExtraType, CGRect)] = []
        for (i, type) in extras.enumerated() {
            let x = stripStartX + CGFloat(i) * (extraIconSize + extraIconGap)
            rects.append((type, CGRect(x: x, y: y, width: extraIconSize, height: extraIconSize)))
        }
        return rects
    }

    public static let extraIconSize: CGFloat = 14
    public static let extraIconGap: CGFloat = 4
    public static let extraIconLeading: CGFloat = 6

    /// Inline emoticon (left of text). nil when the topic has no
    /// `mmd.emoticon` attribute set.
    var emoticonName: String? {
        guard let raw = topic.attribute(TopicAttribute.emoticon),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }

    /// Width consumed by the leading emoticon (icon + 4pt gap), or 0 when
    /// no emoticon. Layout adds it to the element width.
    public var emoticonLeadingWidth: CGFloat {
        emoticonName == nil ? 0 : (Self.emoticonSize + Self.emoticonGap)
    }

    public static let emoticonSize: CGFloat = 14
    public static let emoticonGap: CGFloat = 4

    // Instance accessors for ergonomics.
    var extraIconSize: CGFloat { Self.extraIconSize }
    var extraIconGap: CGFloat { Self.extraIconGap }
    var extraIconLeading: CGFloat { Self.extraIconLeading }

    // MARK: - Per-topic color overrides

    /// Override for the topic's fill, parsed from the `fillColor` attribute.
    /// `nil` when no override is set — caller falls back to the theme.
    public var customFillColor: NSColor? {
        MindMapColor.parse(topic.attribute(TopicAttribute.fillColor))
    }

    public var customBorderColor: NSColor? {
        MindMapColor.parse(topic.attribute(TopicAttribute.borderColor))
    }

    public var customTextColor: NSColor? {
        MindMapColor.parse(topic.attribute(TopicAttribute.textColor))
    }

    // MARK: - Embedded image (mmd.image base64)

    /// Cached decoded image. Lazily reset on `topic.text` mutations is not
    /// needed because the cache key (the attribute string itself) is checked
    /// for parity each access; see `embeddedImage`.
    private var cachedImage: NSImage?
    private var cachedImageKey: String?

    /// Decoded thumbnail from the `mmd.image` attribute, when present.
    public var embeddedImage: NSImage? {
        guard let raw = topic.attribute(TopicAttribute.image), !raw.isEmpty else {
            cachedImage = nil
            cachedImageKey = nil
            return nil
        }
        if cachedImageKey == raw { return cachedImage }
        // Tolerate a "data:image/png;base64,..." prefix as well as raw base64.
        let cleaned: String
        if let comma = raw.firstIndex(of: ","), raw.hasPrefix("data:") {
            cleaned = String(raw[raw.index(after: comma)...])
        } else {
            cleaned = raw
        }
        guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters),
              let image = NSImage(data: data) else {
            cachedImage = nil
            cachedImageKey = raw
            return nil
        }
        cachedImage = image
        cachedImageKey = raw
        return image
    }

    /// Thumbnail rect inside the topic frame (above the text). Returns
    /// `.zero` when the topic has no image.
    public var embeddedImageDrawRect: CGRect {
        let size = embeddedImageDrawSize
        guard size != .zero else { return .zero }
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.minY + 6,
            width: size.width,
            height: size.height
        )
    }

    /// How much vertical space the embedded image consumes inside the
    /// element (above the text). Layout adds this to the element height.
    /// +8 padding between image and text.
    public var embeddedImageHeight: CGFloat {
        let size = embeddedImageDrawSize
        return size == .zero ? 0 : size.height + 8
    }

    /// Scaled size used by both the draw rect and the layout height — fits
    /// the embedded image into the 96×64 thumb box, never upscales.
    private var embeddedImageDrawSize: CGSize {
        guard let image = embeddedImage, image.size.width > 0 else { return .zero }
        let maxWidth: CGFloat = 96
        let maxHeight: CGFloat = 64
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height, 1.0)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }
}
