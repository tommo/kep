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

    // Instance accessors for ergonomics.
    var extraIconSize: CGFloat { Self.extraIconSize }
    var extraIconGap: CGFloat { Self.extraIconGap }
    var extraIconLeading: CGFloat { Self.extraIconLeading }

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
        guard let image = embeddedImage, image.size.width > 0 else { return .zero }
        let maxWidth: CGFloat = 96
        let maxHeight: CGFloat = 64
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height, 1.0)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: frame.midX - drawSize.width / 2,
            y: frame.minY + 6,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    /// How much vertical space the embedded image consumes inside the
    /// element (above the text). Layout adds this to the element height.
    public var embeddedImageHeight: CGFloat {
        guard let image = embeddedImage, image.size.width > 0 else { return 0 }
        let maxWidth: CGFloat = 96
        let maxHeight: CGFloat = 64
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height, 1.0)
        return image.size.height * scale + 8 // +8 padding between image and text
    }
}
