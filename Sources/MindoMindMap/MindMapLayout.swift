import AppKit
import MindoModel

/// Two-pass layout for a mind map. Mirrors the approach in `MindMapCanvas`:
///   1. `measure(...)` walks the tree and assigns each element its own size.
///   2. `layout(...)` recursively places elements via `alignElementAndChildren`,
///      using subtree bounds to space siblings.
public final class MindMapLayout {
    public let theme: MindMapTheme
    public let originPadding: CGFloat = 32

    public init(theme: MindMapTheme) {
        self.theme = theme
    }

    /// Run both passes on `root`, returning the canvas-coordinates bounding box.
    @discardableResult
    public func layout(_ root: MindMapElement) -> CGRect {
        measureRecursive(root)
        balanceRoot(root)

        // Place root at origin (0,0) — view centers later via scrollPoint.
        place(root, at: .zero)
        return root.subtreeBounds.insetBy(dx: -originPadding, dy: -originPadding)
    }

    // MARK: - Pass 1: measure

    private func measureRecursive(_ element: MindMapElement) {
        let font = theme.font(forLevel: element.level)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        // Topic text may contain hard newlines (escaped from <br/> on disk).
        let text = element.topic.text.isEmpty ? " " : element.topic.text
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let insets = theme.textInsets
        let w = ceil(bounding.width) + insets.left + insets.right
        let h = ceil(bounding.height) + insets.top + insets.bottom
        element.elementSize = CGSize(width: max(40, w), height: max(28, h))
        for child in element.children {
            measureRecursive(child)
        }
    }

    // MARK: - Root balancing

    private func balanceRoot(_ root: MindMapElement) {
        guard root.level == 0 else { return }
        // Honor an explicit `leftSide` topic attribute, otherwise alternate.
        var left: [MindMapElement] = []
        var right: [MindMapElement] = []
        for (idx, child) in root.children.enumerated() {
            if let v = child.topic.attribute(TopicAttribute.leftSide), Bool(v) == true {
                child.isLeftSide = true
                left.append(child)
            } else {
                let isLeft = (idx % 2 == 1)
                child.isLeftSide = isLeft
                if isLeft { left.append(child) } else { right.append(child) }
            }
        }
        root.leftChildren = left
        root.rightChildren = right
        // Mark left-sidedness through the entire left subtree (children of left children
        // visually flow leftward too).
        for el in left { propagateLeftSide(el) }
    }

    private func propagateLeftSide(_ element: MindMapElement) {
        element.isLeftSide = true
        for c in element.children { propagateLeftSide(c) }
    }

    // MARK: - Pass 2: place

    /// Place `element` such that the *center* of its element rect is at `center`,
    /// then recursively place children to its right (or left, for left-side).
    private func place(_ element: MindMapElement, at center: CGPoint) {
        if element.level == 0 {
            placeRoot(element, at: center)
            return
        }
        let halfW = element.elementSize.width / 2
        let halfH = element.elementSize.height / 2
        element.frame = CGRect(
            x: center.x - halfW, y: center.y - halfH,
            width: element.elementSize.width, height: element.elementSize.height
        )

        let visible = element.visibleChildren
        guard !visible.isEmpty else {
            element.subtreeBounds = element.frame
            return
        }

        let direction: CGFloat = element.isLeftSide ? -1 : 1
        let childX = element.frame.midX + direction * (halfW + theme.horizontalGap)
        layOutColumn(visible, columnX: childX, parentCenterY: element.frame.midY, side: direction)

        // Subtree bounds = union of self frame + children subtreeBounds.
        var union = element.frame
        for c in visible { union = union.union(c.subtreeBounds) }
        element.subtreeBounds = union
    }

    private func placeRoot(_ root: MindMapElement, at center: CGPoint) {
        let halfW = root.elementSize.width / 2
        let halfH = root.elementSize.height / 2
        root.frame = CGRect(
            x: center.x - halfW, y: center.y - halfH,
            width: root.elementSize.width, height: root.elementSize.height
        )

        let leftChildren = root.isCollapsed ? [] : root.leftChildren
        let rightChildren = root.isCollapsed ? [] : root.rightChildren

        let leftX = root.frame.midX - (halfW + theme.horizontalGap)
        let rightX = root.frame.midX + (halfW + theme.horizontalGap)
        layOutColumn(leftChildren, columnX: leftX, parentCenterY: root.frame.midY, side: -1)
        layOutColumn(rightChildren, columnX: rightX, parentCenterY: root.frame.midY, side: +1)

        var union = root.frame
        for c in leftChildren + rightChildren { union = union.union(c.subtreeBounds) }
        root.subtreeBounds = union
    }

    /// Stack `elements` vertically centered around `parentCenterY` at column x = `columnX`.
    /// Each child's center sits at the column edge facing its parent (right edge for left side).
    private func layOutColumn(_ elements: [MindMapElement], columnX: CGFloat, parentCenterY: CGFloat, side: CGFloat) {
        guard !elements.isEmpty else { return }
        // Tentatively place at y=0; we'll measure subtree heights and recenter.
        var heights: [CGFloat] = []
        var subtreeHeights: [CGFloat] = []
        for el in elements {
            measureSubtreeHeight(el)
            heights.append(el.elementSize.height)
            subtreeHeights.append(el.subtreeHeight)
        }
        let totalHeight = subtreeHeights.reduce(0, +) + theme.verticalGap * CGFloat(elements.count - 1)
        var cursor = parentCenterY - totalHeight / 2
        for (i, el) in elements.enumerated() {
            let centerY = cursor + subtreeHeights[i] / 2
            // For right-side children, child element's left edge is at columnX.
            // For left-side children, child element's right edge is at columnX.
            let cx = side > 0 ? columnX + el.elementSize.width / 2 : columnX - el.elementSize.width / 2
            place(el, at: CGPoint(x: cx, y: centerY))
            cursor += subtreeHeights[i] + theme.verticalGap
        }
    }

    /// Measure the vertical extent that this subtree occupies. Stored as a derived
    /// property on the element so we can reuse it during placement.
    private func measureSubtreeHeight(_ element: MindMapElement) {
        let kids = element.visibleChildren
        if kids.isEmpty {
            element.subtreeHeight = element.elementSize.height
            return
        }
        for k in kids { measureSubtreeHeight(k) }
        let kidsHeight = kids.map(\.subtreeHeight).reduce(0, +) + theme.verticalGap * CGFloat(kids.count - 1)
        element.subtreeHeight = max(element.elementSize.height, kidsHeight)
    }
}

private var subtreeHeightKey: UInt8 = 0

extension MindMapElement {
    /// Cached subtree height. Set by `MindMapLayout`.
    var subtreeHeight: CGFloat {
        get {
            (objc_getAssociatedObject(self, &subtreeHeightKey) as? CGFloat) ?? 0
        }
        set {
            objc_setAssociatedObject(self, &subtreeHeightKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
