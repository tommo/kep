import AppKit
import MindoModel

/// Keyboard handling + zoom helpers for `MindMapView`. The local
/// NSEvent monitor + lifecycle overrides stay in the main file because
/// they own the `keyMonitor` stored property and `viewDidMoveToWindow`
/// override; this extension provides the actual per-key dispatch.
extension MindMapView {

    /// Eat key equivalents for keys we want `keyDown(with:)` to handle —
    /// otherwise NSWindow can grab Tab (focus traversal) or arrow keys
    /// (default key-loop) before they reach us. Returning `false` here
    /// signals the system to fall back to keyDown for non-equivalent keys.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        if window?.firstResponder === self,
           ["\t", "\r", "-", "=", "+", " "].contains(chars) || Self.arrowKeyChars.contains(chars) {
            self.keyDown(with: event)
            return true
        }
        // ⌘ + arrow reorders/reparents the selected topic (outline-style move),
        // distinct from a bare arrow which just moves the selection. Must be
        // caught here in performKeyEquivalent so the window's key loop doesn't
        // consume the arrow first. ⌥ excluded so it can't collide with future
        // option-arrow bindings.
        if window?.firstResponder === self,
           event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.option),
           let direction = Self.arrowKeyDirections[chars] {
            moveSelected(direction)
            return true
        }
        // ⌘D duplicates the selected topic with full subtree (mirror of the
        // context-menu Clone with Subtree). Convention from Finder.
        if window?.firstResponder === self,
           chars == "d", event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.option) {
            if let sel = selectedElement, sel.topic.parent != nil,
               let clone = undoableCloneTopic(sel.topic, deep: true),
               let cloneEl = self.element(forTopic: clone) {
                selectElement(cloneEl)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    public override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else { super.keyDown(with: event); return }
        let isShift = event.modifierFlags.contains(.shift)
        let isOption = event.modifierFlags.contains(.option)

        // ⌥Space = jump-to-root. Must come before the bare-space pan gate
        // below or the modifier would never get a look-in.
        if chars == " ", isOption {
            if let root = rootElement { selectElement(root) }
            return
        }

        if chars == " " {
            if !isSpaceDown {
                isSpaceDown = true
                NSCursor.openHand.push()
            }
            return
        }

        if let direction = Self.arrowKeyDirections[chars] {
            isShift ? extendSelection(direction) : move(direction)
            return
        }

        // F2 = inline-edit selected topic. macOS function-key inputs
        // arrive as the special unichar NSF2FunctionKey (0xF705).
        if chars.unicodeScalars.first?.value == 0xF705,
           let sel = selectedElement {
            beginInlineEdit(on: sel)
            return
        }

        switch chars {
        case "\t": addChild()
        case "\r":
            if isShift { addPreviousSibling() } else { addNextSibling() }
        case "\u{7F}", "\u{08}": deleteSelection()
        case "-":
            toggleCollapse(toCollapsed: true)
        case "=", "+":
            toggleCollapse(toCollapsed: false)
        case "\u{1B}":
            // Esc cancels an in-flight reorder/reparent drag without committing.
            if dragSourceElement != nil { resetDragState() }
            else { super.keyDown(with: event) }
        default:
            super.keyDown(with: event)
        }
    }

    public override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            if isSpaceDown {
                isSpaceDown = false
                NSCursor.pop()
            }
            return
        }
        super.keyUp(with: event)
    }

    // MARK: - Zoom

    /// Snap-step the magnification — used by the App's View menu.
    public func zoom(by factor: CGFloat) {
        guard let scroll = enclosingScrollView else { return }
        scroll.magnification = Self.clampedZoom(
            current: scroll.magnification,
            factor: factor,
            min: scroll.minMagnification,
            max: scroll.maxMagnification
        )
    }

    public func resetZoom() {
        enclosingScrollView?.magnification = 1.0
    }

    /// Fit the entire content into the visible viewport, clamped to the
    /// scroll view's magnification bounds. Also re-centers the scroll
    /// origin on the content midpoint so the root sits in view.
    public func zoomToFit() {
        guard let scroll = enclosingScrollView, contentBounds.width > 0, contentBounds.height > 0 else { return }
        // Use the clip view's *unscaled* visible size so we don't compound
        // an existing magnification.
        let visible = scroll.contentView.bounds.size
        let target = Self.fitMagnification(
            visible: visible,
            content: contentBounds.size,
            min: scroll.minMagnification,
            max: scroll.maxMagnification
        )
        scroll.magnification = target
        // Center on the content midpoint.
        let midPoint = NSPoint(x: contentBounds.midX, y: contentBounds.midY)
        scroll.contentView.scroll(to: NSPoint(
            x: max(0, midPoint.x - visible.width / (2 * target)),
            y: max(0, midPoint.y - visible.height / (2 * target))
        ))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Pure zoom-to-fit math, exposed for unit tests.
    public static func fitMagnification(visible: CGSize, content: CGSize, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        guard content.width > 0, content.height > 0 else { return 1.0 }
        let raw = Swift.min(visible.width / content.width, visible.height / content.height)
        return Swift.max(lower, Swift.min(upper, raw))
    }

    /// Zoom math exposed for unit tests — clamps to a bounded range and snaps
    /// to the supplied factor.
    public static func clampedZoom(current: CGFloat, factor: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        return Swift.max(lower, Swift.min(upper, current * factor))
    }

    // MARK: - Direction-based navigation

    /// Resolve the topic in `direction` of `from`. Used by both the single-
    /// select arrow handler and the multi-select extender.
    ///
    /// Direction is SIDE-AWARE: the map is mirrored about the root, so on the
    /// left half "outward" (toward leaf) is LEFT and "inward" (toward root) is
    /// RIGHT — the reverse of the right half. The old code ignored this and
    /// always treated Right as "into children", so on the left side Right
    /// dived deeper instead of heading back to the parent, and you could never
    /// navigate left-side topics back toward the root — the instability.
    func element(in direction: Direction, of from: MindMapElement) -> MindMapElement? {
        guard let root = rootElement else { return nil }

        func towardParent() -> MindMapElement? {
            guard let parent = from.topic.parent else { return nil }
            return element(forTopic: parent)
        }
        // First *visible* child on `from`'s side (children inherit the side).
        let firstChild = from.children.first

        switch direction {
        case .right:
            if from === root { return root.rightChildren.first }
            // Right-side: inward toward children. Left-side: back toward root.
            return from.isLeftSide ? towardParent() : firstChild
        case .left:
            if from === root { return root.leftChildren.first }
            return from.isLeftSide ? firstChild : towardParent()
        case .up, .down:
            guard let parent = from.topic.parent, let parentEl = element(forTopic: parent) else { return nil }
            let siblings = parentEl.children.filter { $0.isLeftSide == from.isLeftSide }
            if let idx = siblings.firstIndex(where: { $0 === from }) {
                let next = direction == .up ? idx - 1 : idx + 1
                if siblings.indices.contains(next) { return siblings[next] }
            }
            return nil
        }
    }

    func move(_ direction: Direction) {
        guard let sel = selectedElement, let target = element(in: direction, of: sel) else { return }
        selectElement(target)
    }

    /// ⌘ + arrow: structurally move the selected topic (reorder among
    /// siblings, or indent/outdent), then keep it selected at its new spot.
    /// No-op for the root or at a boundary where the move can't happen.
    func moveSelected(_ direction: Direction) {
        guard let sel = selectedElement else { return }
        let topic = sel.topic
        guard let plan = MindMapTopicMove.plan(for: topic, direction: direction) else { return }
        undoableReparent(topic, to: plan.parent, at: plan.index)
        // Elements are rebuilt by the reparent; re-resolve and reselect.
        if let moved = element(forTopic: topic) { selectElement(moved) }
    }
}
