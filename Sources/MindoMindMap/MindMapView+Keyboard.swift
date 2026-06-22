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
        // ⌘ + arrow reorders/reparents the selected topic (outline-style move),
        // distinct from a bare arrow which just moves the selection. This MUST
        // come before the bare-arrow gate below — otherwise that gate swallows
        // every arrow (⌘ or not) into keyDown and the ⌘ move never fires.
        // ⌥ excluded so it can't collide with future option-arrow bindings.
        if window?.firstResponder === self,
           event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.option),
           let direction = Self.arrowKeyDirections[chars] {
            moveSelected(direction)
            return true
        }
        // XMind fold/unfold: ⌘/ toggles the selected topic, ⇧⌘/ toggles all
        // sub-branches under the selection.
        if window?.firstResponder === self,
           chars == "/", event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.option) {
            if event.modifierFlags.contains(.shift) { toggleFoldAllUnderSelection() }
            else { toggleCollapseSelected() }
            return true
        }
        if window?.firstResponder === self,
           ["\t", "\r", " "].contains(chars) || Self.arrowKeyChars.contains(chars) {
            self.keyDown(with: event)
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

        let isCommand = event.modifierFlags.contains(.command)

        switch chars {
        case "\t": addChild()
        case "\r":
            // XMind parity: ⌘Return inserts a PARENT of the selection, plain
            // Return a following sibling, ⇧Return a preceding one.
            if isCommand { addParentTopic() }
            else if isShift { addPreviousSibling() }
            else { addNextSibling() }
        case "\u{7F}", "\u{08}": deleteSelection()
        case "\u{1B}":
            // Esc cancels an in-flight reorder/reparent drag without committing.
            if dragSourceElement != nil { resetDragState() }
            else { super.keyDown(with: event) }
        default:
            // Type-to-edit: a printable character (no ⌘/⌃/⌥) on a selected
            // topic starts editing with that character — the XMind "click and
            // type to replace" flow. Shift is allowed (capital letters).
            if let sel = selectedElement, inlineEditor == nil,
               !isCommand, !isOption, !event.modifierFlags.contains(.control),
               Self.isPrintable(chars) {
                beginInlineEdit(on: sel, initialText: chars)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// A single, printable character suitable for type-to-edit — excludes
    /// control chars, Delete, and the function-key private-use range (arrows,
    /// F-keys) that arrive as high unichars.
    static func isPrintable(_ chars: String) -> Bool {
        guard chars.count == 1, let scalar = chars.unicodeScalars.first else { return false }
        return scalar.value >= 0x20 && scalar.value != 0x7F && scalar.value < 0xF700
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
        // Child to navigate INTO: the one nearest the source node's vertical
        // position, not just the first by index — pressing into a branch should
        // land on the child sitting at roughly the same height (what the eye
        // expects), not jump to the topmost sibling. `visibleChildren` is empty
        // when collapsed, so inward navigation can't land on a hidden topic.
        func inwardChild(_ children: [MindMapElement]) -> MindMapElement? {
            guard !children.isEmpty else { return nil }
            let y = from.frame.midY
            let dists = children.map { (el: $0, d: abs($0.frame.midY - y)) }
            let dMin = dists.map(\.d).min()!
            // Children whose distance is within ~20% of the nearest count as
            // "the same vertical offset" — e.g. the two children straddling the
            // parent's centre are rarely *exactly* equidistant (uneven subtree
            // heights nudge the parent off the midpoint by a few points). Among
            // those, prefer the UPPER one (smaller y on the flipped canvas).
            // A genuinely closer child (outside the band) still wins outright.
            let band = dMin * 0.2 + 1
            return dists.filter { $0.d <= dMin + band }
                        .min { $0.el.frame.midY < $1.el.frame.midY }?.el
        }

        switch direction {
        case .right:
            if from === root { return from.isCollapsed ? nil : inwardChild(root.rightChildren) }
            // Right-side: inward toward children. Left-side: back toward root.
            return from.isLeftSide ? towardParent() : inwardChild(from.visibleChildren)
        case .left:
            if from === root { return from.isCollapsed ? nil : inwardChild(root.leftChildren) }
            return from.isLeftSide ? inwardChild(from.visibleChildren) : towardParent()
        case .up, .down:
            // Purely POSITIONAL: the nearest visible node above/below anywhere on
            // the canvas (nearest row, tie-broken by horizontal closeness), so
            // Up/Down walk in reading order and cross subtree — and side —
            // boundaries instead of dead-ending. The horizontal tie-break keeps
            // you on your own branch while same-row neighbours exist, and only
            // crosses to the other half when that's genuinely the nearest node.
            let candidates = visibleElements().filter { $0 !== from && $0 !== root }
            guard let idx = Self.nearestVertical(from: from.frame,
                                                 candidates: candidates.map(\.frame),
                                                 goingDown: direction == .down) else { return nil }
            return candidates[idx]
        }
    }

    /// Every element currently visible (descendants of a folded node are
    /// excluded, since `visibleChildren` is empty when collapsed).
    func visibleElements() -> [MindMapElement] {
        guard let root = rootElement else { return [] }
        var out: [MindMapElement] = []
        func rec(_ el: MindMapElement) {
            out.append(el)
            for child in el.visibleChildren { rec(child) }
        }
        rec(root)
        return out
    }

    /// Pure geometry for Up/Down arrow navigation: among `candidates` strictly
    /// above (`goingDown == false`) or below `from`, pick the nearest row, then
    /// tie-break by horizontal closeness. Returns the index into `candidates`,
    /// or nil when none lie in that direction. (Canvas is flipped: smaller midY
    /// is visually higher, so "down" means a larger midY.)
    static func nearestVertical(from: CGRect, candidates: [CGRect], goingDown: Bool) -> Int? {
        let fromX = from.midX, fromY = from.midY
        let inDir = candidates.enumerated().filter { _, f in
            goingDown ? f.midY > fromY + 0.5 : f.midY < fromY - 0.5
        }
        guard !inDir.isEmpty else { return nil }
        let dyMin = inDir.map { abs($0.element.midY - fromY) }.min()!
        // Rows within this band of the nearest count as "the same row"; among
        // them the horizontally closest wins, otherwise the closer row wins.
        let band = dyMin * 0.5 + 4
        return inDir.filter { abs($0.element.midY - fromY) <= dyMin + band }
                    .min { abs($0.element.midX - fromX) < abs($1.element.midX - fromX) }?.offset
    }

    func move(_ direction: Direction) {
        guard let sel = selectedElement else { return }
        // Arrow INTO a collapsed node auto-expands it, then steps onto a child
        // (XMind behaviour) — otherwise navigating inward to a folded branch
        // would just stall.
        if sel.isCollapsed, !sel.children.isEmpty, isInwardDirection(direction, for: sel) {
            undoableSetAttribute(sel.topic, key: TopicAttribute.collapsed, value: nil)
            if let selAfter = element(forTopic: sel.topic),
               let target = element(in: direction, of: selAfter) {
                selectElement(target)
            }
            return
        }
        guard let target = element(in: direction, of: sel) else { return }
        selectElement(target)
    }

    /// Whether `direction` heads INTO `el`'s children (vs back toward the root).
    /// Right-side topics open with Right, left-side topics with Left.
    private func isInwardDirection(_ direction: Direction, for el: MindMapElement) -> Bool {
        guard el !== rootElement else { return false }   // root is never collapsed
        return el.isLeftSide ? (direction == .left) : (direction == .right)
    }

    /// ⌘ + arrow: structurally move the selected topic (reorder among
    /// siblings, or indent/outdent), then keep it selected at its new spot.
    /// No-op for the root or at a boundary where the move can't happen.
    func moveSelected(_ direction: Direction) {
        guard let sel = selectedElement else { return }
        let topic = sel.topic
        // A root child has no grandparent to outdent into, so a horizontal move
        // that pushes it ACROSS the root instead flips which side it hangs off:
        // a right-side child pushed Left jumps to the left half (and vice
        // versa). This is the only way to put nodes on the root's left side.
        if topic.parent === mindMap?.root {
            let toLeft = (direction == .left && !sel.isLeftSide)
            let toRight = (direction == .right && sel.isLeftSide)
            if toLeft || toRight {
                undoableSetAttribute(topic, key: TopicAttribute.leftSide,
                                     value: toLeft ? "true" : "false")
                rebuildElementsPublic()
                if let moved = element(forTopic: topic) { selectElement(moved) }
                return
            }
        }
        let wasLeftSide = sel.isLeftSide
        guard let plan = MindMapTopicMove.plan(for: topic, direction: direction) else { return }
        undoableReparent(topic, to: plan.parent, at: plan.index)
        // When the move lands the topic directly under the ROOT (an outdent, or
        // a reorder among root children), pin an explicit side matching the one
        // it visually came from. Otherwise balanceRoot re-derives the side from
        // index parity and can flip the node to the opposite half — the cursor
        // appears to teleport across the map (bug #39/#40, same fix as
        // addNextSibling's inheritRootSide).
        if plan.parent === mindMap?.root {
            topic.setAttribute(TopicAttribute.leftSide, wasLeftSide ? "true" : "false")
            rebuildElementsPublic()
        }
        // Elements are rebuilt by the reparent; re-resolve and reselect.
        if let moved = element(forTopic: topic) { selectElement(moved) }
    }
}

// MARK: - Inline-edit field delegate (commit-and-create flow)

extension MindMapView: NSTextFieldDelegate {

    /// Grow the inline editor to fit the text as the user types, keeping it
    /// centered on the node being edited — so the box visibly expands instead
    /// of clipping the text behind the original (small) node size.
    public func controlTextDidChange(_ obj: Notification) {
        guard let field = inlineEditor, field === (obj.object as? NSTextField),
              let topic = inlineEditTarget, let el = element(forTopic: topic) else { return }
        let font = field.font ?? theme.font(forLevel: el.level)
        let size = InlineEditSizing.fittingSize(
            text: field.stringValue, font: font, insets: theme.textInsets)
        let center = CGPoint(x: el.frame.midX, y: el.frame.midY)
        field.frame = CGRect(
            x: center.x - size.width / 2, y: center.y - size.height / 2,
            width: size.width, height: size.height)
    }

    /// While the inline editor is up, Return commits and creates a following
    /// sibling, Tab commits and creates a child, ⇧Tab just commits, and Esc
    /// cancels — the fast XMind/MindNode outlining flow where you never leave
    /// the keyboard. Each create re-opens the editor on the new topic.
    public func control(_ control: NSControl, textView: NSTextView,
                        doCommandBy commandSelector: Selector) -> Bool {
        guard control === inlineEditor else { return false }
        switch commandSelector {
        // While EDITING, the finishing keys all just commit and keep the SAME
        // topic selected — NO node is created and the cursor never warps.
        // (Bug report: "finish editing → the cursor warped to another node.")
        // Node creation is a SELECTED-mode action: press Return for a sibling
        // or Tab for a child once the edit is finished. This matches XMind,
        // where Enter/Tab create topics on a *selected* (not editing) topic.
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertBacktab(_:)):
            let edited = inlineEditTarget
            commitInlineEdit()
            if let t = edited, let el = element(forTopic: t) { selectElement(el) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelInlineEdit()
            return true
        default:
            return false
        }
    }
}
