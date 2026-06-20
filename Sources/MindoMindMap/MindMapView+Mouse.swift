import AppKit
import MindoCore
import MindoModel

/// Mouse handling for `MindMapView` — split out so the core file stays
/// focused on init / state / responder. Touches drag-state members that
/// were bumped from `private` → file-internal so this extension can read
/// and mutate them.
extension MindMapView {

    public override func rightMouseDown(with event: NSEvent) {
        commitInlineEdit()
        let p = convert(event.locationInWindow, from: nil)
        guard let element = element(at: p) else { return }
        selectElement(element)
        // Arm a potential link-drag. Whether this becomes a link (dragged onto
        // another node) or a context menu (no drag) is decided on rightMouseUp.
        linkDragSource = element
        linkDragOrigin = p
        linkDragCurrent = nil
        linkDragTarget = nil
    }

    public override func rightMouseDragged(with event: NSEvent) {
        guard let source = linkDragSource, let origin = linkDragOrigin else { return }
        let p = convert(event.locationInWindow, from: nil)
        if linkDragCurrent == nil, hypot(p.x - origin.x, p.y - origin.y) < dragThreshold { return }
        linkDragCurrent = p
        // Candidate target = a different node under the cursor.
        linkDragTarget = element(at: p).flatMap { $0 === source ? nil : $0 }
        needsDisplay = true
    }

    public override func rightMouseUp(with event: NSEvent) {
        defer {
            linkDragSource = nil; linkDragOrigin = nil
            linkDragCurrent = nil; linkDragTarget = nil
            needsDisplay = true
        }
        let p = convert(event.locationInWindow, from: nil)
        if linkDragCurrent != nil {
            // It was a drag → make a jump-link if released over another node.
            if let source = linkDragSource { completeLinkDrag(from: source, at: p) }
            return
        }
        // No drag → the classic right-click context menu.
        if let source = linkDragSource {
            NSMenu.popUpContextMenu(makeContextMenu(for: source), with: event, for: self)
        }
    }

    /// Create a topic jump-link from `source` to whatever node is under `p`.
    /// Returns whether a link was made (false if `p` isn't over a different
    /// node). Selects the target so the user sees where the link points.
    @discardableResult
    func completeLinkDrag(from source: MindMapElement, at p: CGPoint) -> Bool {
        guard let target = element(at: p), target !== source else { return false }
        undoableLinkTopic(source.topic, to: target.topic)
        selectElement(target)
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        commitInlineEdit()
        hideNotePopover()
        let p = convert(event.locationInWindow, from: nil)
        // Space-drag wins over everything — it's a temporary "pan" mode.
        if isSpaceDown, let scroll = enclosingScrollView {
            panOriginInWindow = event.locationInWindow
            panStartScroll = scroll.contentView.bounds.origin
            return
        }
        // Extra-icon hit-test runs first so clicks on the icon strip don't
        // start a drag or change selection.
        if let (el, type) = elementExtra(at: p) {
            handleExtraTap(on: el, type: type)
            return
        }
        // Collapsator hit-test: a click on the fold circle toggles the node's
        // collapsed state (undoable) without starting a drag or editing. Runs
        // before the marquee/selection path because the circle sits OUTSIDE the
        // node frame, where element(at:) would otherwise read empty canvas.
        if let el = collapseIndicator(at: p) {
            selectElement(el)
            undoableSetAttribute(el.topic, key: TopicAttribute.collapsed,
                                 value: el.isCollapsed ? nil : "true")
            return
        }
        // Embedded-image hit: open the lightbox at full resolution.
        if event.clickCount >= 1, let image = embeddedImage(at: p) {
            MindMapImageLightbox.present(image: image, near: window)
            return
        }
        let el = element(at: p)
        // Cmd-click toggles multi-selection, Shift-click on a NODE adds it;
        // otherwise replace. Shift on EMPTY canvas falls through to the marquee.
        if event.modifierFlags.contains(.command) {
            toggleSelection(el)
        } else if event.modifierFlags.contains(.shift), let el = el {
            selectedTopics.insert(ObjectIdentifier(el.topic))
            selectedElement = el
            needsDisplay = true
        } else if el == nil {
            if event.modifierFlags.contains(.shift) {
                // Shift + empty-canvas drag: rubber-band marquee select. Don't
                // clear the selection yet — mouseUp tells a click (clears) from
                // a drag (selects the enclosed topics).
                marqueeStart = p
                marqueeCurrent = nil
            } else if let scroll = enclosingScrollView {
                // Plain empty-canvas drag = pan the canvas (hand tool) — the
                // primary way to navigate a large map with a mouse. A press
                // that never moves is treated as a click and clears selection
                // (handled in mouseUp).
                panOriginInWindow = event.locationInWindow
                panStartScroll = scroll.contentView.bounds.origin
                emptyCanvasPan = true
                NSCursor.closedHand.push()
            } else {
                // No scroll view (headless / export): nothing to pan, so a
                // bare empty press just clears the selection.
                selectElement(nil)
            }
        } else {
            selectElement(el)
        }
        if event.clickCount == 2, let el = el {
            // Double-click edits. beginInlineEdit makes the field editor the
            // first responder — DON'T steal it back to the canvas below, or
            // the user couldn't type into the editor they just opened.
            beginInlineEdit(on: el)
            return
        }
        if let el = el, el.topic.parent != nil,
           !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) {
            dragOrigin = p
            dragSourceElement = el
            // ⌥-drag = free move (manual offset) instead of reparent/reorder.
            dragIsFreeMove = event.modifierFlags.contains(.option)
        }
        window?.makeFirstResponder(self)
    }

    public override func mouseDragged(with event: NSEvent) {
        // Space-drag pan: translate the scroll view's clip origin by the
        // window-space delta since mouseDown.
        if let panOrigin = panOriginInWindow, let panStart = panStartScroll, let scroll = enclosingScrollView {
            let dx = event.locationInWindow.x - panOrigin.x
            let dy = event.locationInWindow.y - panOrigin.y
            // isFlipped → AppKit's bounds y grows downward inside the clip view.
            let target = NSPoint(x: panStart.x - dx, y: panStart.y + dy)
            let clip = scroll.contentView
            // Apply the clip's bounds constraint (direct scroll(to:) bypasses it)
            // so drag-pan keeps the content visible like scroll-pan does.
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: target, size: clip.bounds.size)).origin)
            scroll.reflectScrolledClipView(clip)
            return
        }
        // Marquee area-select: update the live corner and select every topic
        // the rubber-band rect catches.
        if let start = marqueeStart {
            let p = convert(event.locationInWindow, from: nil)
            marqueeCurrent = p
            updateMarqueeSelection(start: start, current: p)
            needsDisplay = true
            return
        }
        guard let origin = dragOrigin, let source = dragSourceElement else { return }
        let p = convert(event.locationInWindow, from: nil)
        if dragGhostCenter == nil {
            // Wait until we move past the threshold before showing the ghost.
            if hypot(p.x - origin.x, p.y - origin.y) < dragThreshold { return }
        }
        dragGhostCenter = p
        // ⌥ free move: no reparent/insertion targets — the ghost just tracks
        // the cursor and mouseUp commits the manual offset.
        if dragIsFreeMove {
            dragInsertionTarget = nil
            dragRootSide = nil
            dragTargetElement = nil
            autoScrollDuringDrag(cursor: p)
            needsDisplay = true
            return
        }
        // Auto-scroll when the drag nears a viewport edge so off-screen drop
        // targets are reachable without releasing. Pure ramp math; applied to
        // the clip view here.
        autoScrollDuringDrag(cursor: p)
        // "Drop between siblings" wins over "drop onto topic" — when the
        // cursor lands in a gap among the source's existing siblings, show
        // the insertion indicator instead of highlighting a parent.
        if let ins = candidateInsertionTarget(under: p, source: source) {
            dragInsertionTarget = ins
            dragRootSide = nil
            dragTargetElement = nil
        } else if let rs = rootSideInsertion(under: p, source: source) {
            // Dragging beside the root → drop as a root child on that side
            // (the drag way to populate the left half). Shows a hint line
            // beside the root even when that side is empty.
            dragInsertionTarget = rs.target
            dragRootSide = rs.isLeft
            dragTargetElement = nil
        } else {
            dragInsertionTarget = nil
            dragRootSide = nil
            let target = candidateDropTarget(under: p, excluding: source)
            // Auto-unfold a collapsed drop target so the user can re-target
            // into its children. Cleared on dragExited via resetDragState's
            // re-render. Live edit (no undo step) — the fold flip would
            // otherwise stack a confusing entry on the undo manager.
            if let t = target,
               t.topic.attribute(TopicAttribute.collapsed) == "true",
               !t.children.isEmpty {
                t.topic.setAttribute(TopicAttribute.collapsed, nil)
                rebuildElementsPublic()
            }
            dragTargetElement = target
        }
        needsDisplay = true
    }

    /// Nudge the enclosing scroll view when the drag cursor is within the
    /// edge margin, so a topic can be dragged to an off-screen target.
    private func autoScrollDuringDrag(cursor: CGPoint) {
        guard let scroll = enclosingScrollView else { return }
        let delta = MindMapAutoScroll.delta(
            point: cursor, visibleRect: visibleRect, margin: 50, maxSpeed: 24)
        guard delta != .zero else { return }
        let origin = scroll.contentView.bounds.origin
        scroll.contentView.scroll(to: NSPoint(x: origin.x + delta.dx, y: origin.y + delta.dy))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Set the selection to the topics enclosed by the current marquee rect.
    private func updateMarqueeSelection(start: CGPoint, current: CGPoint) {
        guard let root = rootElement else { return }
        let rect = MindMapAreaSelection.rect(from: start, to: current)
        var all: [MindMapElement] = []
        root.traverse { all.append($0) }
        let hits = MindMapAreaSelection.enclosed(all, frame: { $0.frame }, in: rect)
        selectedTopics = Set(hits.map { ObjectIdentifier($0.topic) })
        selectedElement = hits.last
    }

    public override func mouseUp(with event: NSEvent) {
        if panOriginInWindow != nil {
            let start = panStartScroll
            let wasEmptyCanvasPan = emptyCanvasPan
            panOriginInWindow = nil
            panStartScroll = nil
            if emptyCanvasPan {
                emptyCanvasPan = false
                NSCursor.pop()
            }
            // An empty-canvas press that never actually panned is a plain
            // click on the background → clear the selection.
            if wasEmptyCanvasPan,
               (enclosingScrollView?.contentView.bounds.origin ?? .zero) == (start ?? .zero) {
                selectElement(nil)
            }
            return
        }
        // Finish a marquee: a real drag already set the selection; a bare
        // click (no drag) on empty canvas clears it.
        if let start = marqueeStart {
            if marqueeCurrent == nil { selectElement(nil) }
            marqueeStart = nil
            marqueeCurrent = nil
            needsDisplay = true
            return
        }
        defer { resetDragState() }
        guard let source = dragSourceElement, dragGhostCenter != nil else { return }
        // ⌥ free move: commit a manual offset = previous offset + drag delta.
        if dragIsFreeMove, let origin = dragOrigin, let drop = dragGhostCenter {
            let old = source.manualOffset
            let nx = old.x + (drop.x - origin.x)
            let ny = old.y + (drop.y - origin.y)
            groupedUndo(name: "Move Node") {
                undoableSetAttribute(source.topic, key: TopicAttribute.offsetX,
                                     value: abs(nx) < 0.5 ? nil : String(format: "%.1f", nx))
                undoableSetAttribute(source.topic, key: TopicAttribute.offsetY,
                                     value: abs(ny) < 0.5 ? nil : String(format: "%.1f", ny))
            }
            if let moved = element(forTopic: source.topic) { selectElement(moved) }
            return
        }
        if let ins = dragInsertionTarget {
            // Reorder among siblings — index already accounts for source's
            // current position via undoableReparent's remove-then-insert.
            if let side = dragRootSide {
                // Dropped beside the root: reparent under root AND stamp the
                // side so it hangs off the chosen half.
                groupedUndo(name: "Move Topic") {
                    undoableReparent(source.topic, to: ins.parent.topic, at: ins.index)
                    undoableSetAttribute(source.topic, key: TopicAttribute.leftSide,
                                         value: side ? "true" : "false")
                }
            } else {
                undoableReparent(source.topic, to: ins.parent.topic, at: ins.index)
            }
            if let moved = element(forTopic: source.topic) { selectElement(moved) }
            return
        }
        guard let target = dragTargetElement else { return }
        // When the dragged topic is part of a multi-selection, move ALL of
        // them under the target (descendants pruned, cycles/no-ops dropped);
        // otherwise just the dragged topic. (R12: drag previously moved only
        // the primary, silently leaving the rest behind.)
        let selected = selectionTopics()
        let candidates = (selected.count > 1 && selected.contains { $0 === source.topic })
            ? selected
            : [source.topic]
        let movers = MindMapSelection.reparentable(candidates, under: target.topic)
        guard !movers.isEmpty else { return }
        // Drop onto a collapsed parent auto-unfolds it (mindolph parity:
        // ckbUnfoldCollapsedDropTarget). Without this the dropped subtree
        // disappears the instant it lands. Done BEFORE reparent so the
        // unfold + reparent share a single visible state transition.
        groupedUndo(name: movers.count > 1 ? "Move Topics" : "Move Topic") {
            if PrefKeys.bool(PrefKeys.mindmapUnfoldCollapsedDropTarget, fallback: true),
               target.isCollapsed {
                undoableSetAttribute(target.topic, key: TopicAttribute.collapsed, value: nil)
            }
            for topic in movers {
                undoableReparent(topic, to: target.topic, at: target.topic.children.count)
            }
        }
        if let moved = element(forTopic: source.topic) { selectElement(moved) }
    }

    func resetDragState() {
        if dragGhostCenter != nil || dragTargetElement != nil || dragInsertionTarget != nil {
            dragGhostCenter = nil
            dragTargetElement = nil
            dragInsertionTarget = nil
            dragRootSide = nil
            needsDisplay = true
        }
        dragOrigin = nil
        dragSourceElement = nil
        dragIsFreeMove = false
    }

    /// Detect a "drop beside the root" placement: the cursor is level with the
    /// root and out past one of its sides. Returns an insertion target (a hint
    /// line beside the root + the index in root.children) plus which side, even
    /// when that side has no children yet — the only drag route to the root's
    /// left half. nil when the cursor isn't in a root-side zone.
    func rootSideInsertion(under p: CGPoint, source: MindMapElement)
        -> (target: (parent: MindMapElement, index: Int, lineY: CGFloat, lineMinX: CGFloat, lineMaxX: CGFloat), isLeft: Bool)?
    {
        guard let root = rootElement, source !== root, source.topic.parent != nil else { return nil }
        // Only an EMPTY-space drop beside the root — if the cursor is over an
        // actual node, that node is the drop target (reparent onto it), not a
        // root-side placement. (Without this, dragging onto a right-side child
        // was hijacked into a root-side drop.)
        guard element(at: p) == nil else { return nil }
        let rf = root.frame
        // Vertical band: roughly level with the root (its height + slack).
        let vPad: CGFloat = 90
        guard p.y >= rf.minY - vPad, p.y <= rf.maxY + vPad else { return nil }
        let isLeft = p.x < rf.midX
        // Must be out past the corresponding edge (a bit of slack inward).
        let slack: CGFloat = 30
        if isLeft { guard p.x < rf.minX + slack else { return nil } }
        else      { guard p.x > rf.maxX - slack else { return nil } }

        // Place among that side's children by Y (excluding the source).
        let side = root.children
            .filter { $0 !== source && $0.isLeftSide == isLeft }
            .sorted { $0.frame.midY < $1.frame.midY }
        let k = side.filter { $0.frame.midY < p.y }.count   // how many sit above the cursor

        // Index within root.children: before the k-th same-side child, else append.
        let index: Int
        if k < side.count, let i = root.children.firstIndex(where: { $0 === side[k] }) {
            index = i
        } else {
            index = root.children.count
        }

        // Hint line: a short stub just beside the root on that side, at the gap Y.
        let lineY: CGFloat
        if side.isEmpty { lineY = rf.midY }
        else if k == 0 { lineY = side[0].frame.minY - 6 }
        else if k >= side.count { lineY = side[side.count - 1].frame.maxY + 6 }
        else { lineY = (side[k - 1].frame.maxY + side[k].frame.minY) / 2 }

        let lineMinX = isLeft ? rf.minX - 72 : rf.maxX + 12
        let lineMaxX = isLeft ? rf.minX - 12 : rf.maxX + 72
        return ((root, index, lineY, lineMinX, lineMaxX), isLeft)
    }

    /// Find a "drop between siblings" insertion target. Walks the source's
    /// current parent's children (filtered to the same side for root
    /// children), maps them to Y-ranges, and uses MindMapDragGap to map the
    /// probe to a gap index — then translates that back to the children
    /// array. Returns nil when the cursor isn't in any gap or strays far
    /// from the sibling X-band (so we don't fight with reparent drops).
    func candidateInsertionTarget(under p: CGPoint, source: MindMapElement)
        -> (parent: MindMapElement, index: Int, lineY: CGFloat, lineMinX: CGFloat, lineMaxX: CGFloat)?
    {
        // 1. Reorder among the source's OWN siblings (same side).
        if let parentTopic = source.topic.parent,
           let parentEl = element(forTopic: parentTopic),
           let r = insertionGap(in: parentEl, under: p, source: source, sideFilter: source.isLeftSide) {
            return r
        }
        // 2. Insert into ANOTHER parent: scan every parent whose children form
        //    a gap under the cursor. Unlike a node hit-test, this works over the
        //    empty space *between* a branch's children, so you can drop into a
        //    precise slot. Pick the closest matching gap.
        var best: (result: (parent: MindMapElement, index: Int, lineY: CGFloat, lineMinX: CGFloat, lineMaxX: CGFloat), dist: CGFloat)?
        rootElement?.traverse { el in
            guard !el.children.isEmpty, el !== source else { return }
            // Skip the source's own parent (case 1 handles reorder there) and
            // any parent inside the source's own subtree (can't drop into self).
            if el.topic === source.topic.parent { return }
            if isInSubtree(el.topic, of: source.topic) { return }
            let side: Bool? = el.level == 0 ? (p.x < el.frame.midX) : nil
            if let r = insertionGap(in: el, under: p, source: source, sideFilter: side) {
                let dist = abs(r.lineY - p.y)
                if best == nil || dist < best!.dist { best = (r, dist) }
            }
        }
        return best?.result
    }

    /// True when `node` is `ancestor` or lies within `ancestor`'s subtree.
    private func isInSubtree(_ node: Topic, of ancestor: Topic) -> Bool {
        var t: Topic? = node
        while let cur = t {
            if cur === ancestor { return true }
            t = cur.parent
        }
        return false
    }

    /// Gap-insertion target among `parentEl`'s children (excluding `source`).
    /// `sideFilter` limits to one side (for root, whose children split L/R);
    /// nil considers all children. Returns nil when the cursor isn't in a valid
    /// gap / X-band, so the caller can fall back to reparent-onto.
    private func insertionGap(
        in parentEl: MindMapElement, under p: CGPoint, source: MindMapElement, sideFilter: Bool?
    ) -> (parent: MindMapElement, index: Int, lineY: CGFloat, lineMinX: CGFloat, lineMaxX: CGFloat)? {
        let siblings = parentEl.children.filter {
            $0 !== source && (sideFilter == nil || $0.isLeftSide == sideFilter)
        }
        guard !siblings.isEmpty else { return nil }
        let sortedSiblings = siblings.sorted { $0.frame.minY < $1.frame.minY }
        let ranges = sortedSiblings.map { MindMapDragGap.YRange($0.frame.minY, $0.frame.maxY) }

        // Don't activate if the cursor is far outside the sibling X-band —
        // otherwise dragging across the canvas to reparent flickers.
        let minX = sortedSiblings.map(\.frame.minX).min() ?? 0
        let maxX = sortedSiblings.map(\.frame.maxX).max() ?? 0
        let hPad: CGFloat = 60
        guard p.x >= minX - hPad, p.x <= maxX + hPad else { return nil }

        // Stay within this parent's children Y-band (+ small margin). Without
        // this, sibling columns that share an X (e.g. two parents stacked
        // vertically) would all claim the cursor — dragging down into a lower
        // branch's gap wrongly counted as "append to the upper branch".
        let topY = sortedSiblings.first!.frame.minY
        let botY = sortedSiblings.last!.frame.maxY
        let vPad: CGFloat = 28
        guard p.y >= topY - vPad, p.y <= botY + vPad else { return nil }

        guard let gap = MindMapDragGap.gapIndex(for: p.y, sortedRanges: ranges) else { return nil }

        // Map gap (in sortedSiblings space) → insertion index for
        // undoableReparent, whose convention is the FINAL index *after* the
        // source has been removed (it removes-then-appends-then-moves). So the
        // index must be computed against the children array with the source
        // EXCLUDED — otherwise dragging a node downward past later siblings
        // lands it one slot too far (it slid to the end instead of into the
        // gap). Other-side root children stay in the array; only the source is
        // dropped.
        let insertBefore: MindMapElement? = gap < sortedSiblings.count ? sortedSiblings[gap] : nil
        let childrenWithoutSource = parentEl.children.filter { $0 !== source }
        let insertIndex: Int
        if let target = insertBefore,
           let idx = childrenWithoutSource.firstIndex(where: { $0 === target }) {
            insertIndex = idx
        } else {
            insertIndex = childrenWithoutSource.count
        }

        // Indicator Y: midpoint of the gap (or just above first / below last).
        let lineY: CGFloat
        if gap == 0 {
            lineY = sortedSiblings[0].frame.minY - 4
        } else if gap == sortedSiblings.count {
            lineY = sortedSiblings.last!.frame.maxY + 4
        } else {
            lineY = (sortedSiblings[gap - 1].frame.maxY + sortedSiblings[gap].frame.minY) / 2
        }
        return (parentEl, insertIndex, lineY, minX, maxX)
    }

    /// Find a valid drop-target element under `point`. A target is valid when
    /// it is neither the dragged topic itself nor any of its descendants.
    func candidateDropTarget(under point: CGPoint, excluding source: MindMapElement) -> MindMapElement? {
        guard let hit = element(at: point) else { return nil }
        if hit.topic === source.topic { return nil }
        // Walk up from the hit candidate to make sure it's not inside the source subtree.
        var t: Topic? = hit.topic
        while let cur = t {
            if cur === source.topic { return nil }
            t = cur.parent
        }
        return hit
    }

    /// Hit-test for the embedded image inside any topic. Used by mouseDown
    /// to open the lightbox when the user clicks on the thumbnail.
    func embeddedImage(at point: CGPoint) -> NSImage? {
        guard let root = rootElement else { return nil }
        var hit: NSImage? = nil
        root.traverse { el in
            if hit != nil { return }
            if let image = el.embeddedImage,
               el.embeddedImageDrawRect.contains(point) {
                hit = image
            }
        }
        return hit
    }

    /// Find the (element, extra-type) under `point`. Returns nil when no
    /// extra icon is hit. Used by mouseDown so clicks on the icon strip
    /// dispatch the extra's action instead of starting a drag.
    func elementExtra(at point: CGPoint) -> (MindMapElement, ExtraType)? {
        guard let root = rootElement else { return nil }
        var hit: (MindMapElement, ExtraType)?
        root.traverse { el in
            if hit != nil { return }
            for (type, rect) in el.extraIconRects where rect.contains(point) {
                hit = (el, type)
            }
        }
        return hit
    }

    // MARK: - Hover cursor (pan affordance)

    /// A single tracking area over the visible rect so we get mouseMoved and
    /// can switch the cursor to an open hand over empty canvas — the standard
    /// "you can drag here to pan" hint that makes the pan gesture discoverable.
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        // Never fight an in-progress pan (closed hand) or a held-Space pan
        // (open hand already pushed).
        guard !isSpaceDown, panOriginInWindow == nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        // One combined hit-test per move instead of five separate full-tree
        // traversals (4 inside isPannableCanvas + 1 in updateNoteHover).
        let hit = hitTest(at: p)
        if enclosingScrollView != nil, hit.isEmptyCanvas {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
        updateNoteHover(at: p, extra: hit.extra)
    }

    /// The four canvas hit categories resolved in a single tree walk. Built so
    /// the per-mouse-move cursor + note-hover work doesn't re-traverse the
    /// whole element tree once per category.
    struct CanvasHit {
        var element: MindMapElement?
        var extra: (MindMapElement, ExtraType)?
        var collapse: MindMapElement?
        var image: NSImage?
        /// Empty canvas — a plain drag here pans.
        var isEmptyCanvas: Bool { element == nil && extra == nil && collapse == nil && image == nil }
    }

    /// Resolve all four hit categories under `point` in one traversal,
    /// preserving each category's original selection rule: `element` keeps the
    /// last (topmost) match; extra/collapse/image keep the first match.
    func hitTest(at point: CGPoint) -> CanvasHit {
        var h = CanvasHit()
        guard let root = rootElement else { return h }
        root.traverse { el in
            if el.frame.insetBy(dx: -2, dy: -2).contains(point) { h.element = el }
            if h.extra == nil {
                for (type, rect) in el.extraIconRects where rect.contains(point) { h.extra = (el, type) }
            }
            if h.collapse == nil, let rect = el.collapseIndicatorRect, rect.contains(point) { h.collapse = el }
            if h.image == nil, let image = el.embeddedImage, el.embeddedImageDrawRect.contains(point) { h.image = image }
        }
        return h
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Don't hide outright — moving the cursor ONTO the popover counts as
        // exiting the canvas's tracking area. Schedule the grace-period check,
        // which keeps the popover open while the cursor is over it.
        if notePopover?.isShown == true { scheduleNoteHoverDismiss() }
    }

    /// True when `point` is empty canvas — no topic, extra icon, collapsator,
    /// or embedded image under it — i.e. a plain drag there would pan. Pure
    /// hit-test composition, so the cursor decision is unit-testable.
    func isPannableCanvas(at point: CGPoint) -> Bool {
        hitTest(at: point).isEmptyCanvas
    }

    /// Find the element whose collapsator circle contains `point`, if any.
    /// Used by mouseDown so a click on the fold circle toggles collapse.
    func collapseIndicator(at point: CGPoint) -> MindMapElement? {
        guard let root = rootElement else { return nil }
        var hit: MindMapElement?
        root.traverse { el in
            if hit != nil { return }
            if let rect = el.collapseIndicatorRect, rect.contains(point) { hit = el }
        }
        return hit
    }

    func handleExtraTap(on element: MindMapElement, type: ExtraType) {
        guard let extra = element.topic.extra(type) else { return }
        switch type {
        case .link:
            if let url = URL(string: extra.value) {
                NSWorkspace.shared.open(url)
            }
        case .file:
            let pathOrURL = extra.value
            let url: URL
            if let parsed = URL(string: pathOrURL), parsed.scheme != nil {
                url = parsed
            } else {
                url = URL(fileURLWithPath: pathOrURL)
            }
            onExtraFileTap?(url)
        case .topic:
            followTopicLink(uid: extra.value)
            onExtraTopicTap?(extra.value)
        case .note:
            // The note is peeked on hover (a popover — see updateNoteHover). A
            // click just selects the node so its note opens in the inspector's
            // editor; the old modal NSAlert popup was needless friction.
            if let custom = onExtraNoteTap {
                custom(element.topic, extra.value)
            } else {
                selectElement(element)
            }
        case .unknown:
            break
        }
    }

    // MARK: - Note hover popover

    /// Show/hide the note-preview popover based on the cursor position. Driven
    /// from mouseMoved so hovering a note icon reliably pops a rendered preview
    /// (a native tooltip was inconsistent and plain-text only). Idempotent: the
    /// popover for an already-hovered note isn't rebuilt.
    func updateNoteHover(at point: CGPoint, extra: (MindMapElement, ExtraType)? = nil) {
        let extraHit = extra ?? elementExtra(at: point)
        if let (el, type) = extraHit, type == .note,
           let note = el.topic.extra(.note)?.value,
           !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Over a note icon: keep it open (cancel any pending dismissal).
            cancelNoteHoverDismiss()
            if notePopoverElement === el, notePopover?.isShown == true { return }
            showNotePopover(for: el, markdown: note)
        } else if notePopover?.isShown == true {
            // Left the icon: don't slam it shut — give the cursor time to reach
            // the popover, and keep it alive while the cursor is over it.
            scheduleNoteHoverDismiss()
        }
    }

    private func showNotePopover(for element: MindMapElement, markdown: String) {
        hideNotePopover()
        guard let rect = element.extraIconRects.first(where: { $0.0 == .note })?.1 else { return }
        let pop = NSPopover()
        // .applicationDefined: AppKit must NOT auto-close it. A .transient /
        // .semitransient popover is dismissed by AppKit the instant the mouse
        // moves outside it, which fired before our grace-period logic could run
        // — so moving toward the popover killed it and it was impossible to
        // interact with. We own open/close entirely (hover-intent + keep-alive).
        pop.behavior = .applicationDefined
        pop.animates = false
        pop.contentViewController = NoteHoverController(markdown: markdown)
        pop.show(relativeTo: rect, of: self, preferredEdge: .maxY)
        notePopover = pop
        notePopoverElement = element
    }

    func hideNotePopover() {
        cancelNoteHoverDismiss()
        notePopover?.performClose(nil)
        notePopover = nil
        notePopoverElement = nil
    }

    func cancelNoteHoverDismiss() {
        noteHoverDismiss?.cancel()
        noteHoverDismiss = nil
    }

    /// Close the popover after a short grace period — unless the cursor is now
    /// over the popover itself, in which case keep it open and re-check soon.
    /// This is what lets the user move off the icon and into the note to scroll
    /// it or click a link without it vanishing.
    private func scheduleNoteHoverDismiss() {
        noteHoverDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let win = self.notePopover?.contentViewController?.view.window,
               win.frame.contains(NSEvent.mouseLocation) {
                self.scheduleNoteHoverDismiss()   // still hovering the note — recheck
                return
            }
            self.hideNotePopover()
        }
        noteHoverDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Resolve an `ExtraTopic` jump-link UID to its target node and select it —
    /// `selectElement` scrolls the target into view, so the jump "navigates".
    /// No-op when the UID resolves to nothing (e.g. the target was deleted).
    func followTopicLink(uid: String) {
        guard let map = mindMap,
              let target = map.findTopic(uid: uid),
              let el = element(forTopic: target) else { return }
        selectElement(el)
    }

    // MARK: - Trackpad pinch

    /// Pinch-to-zoom on the canvas. NSScrollView's built-in pinch only
    /// gives a rubber-band overlay that snaps back; this commits the
    /// magnification so the zoom sticks. Centered on the gesture so the
    /// content under the user's fingers stays put.
    public override func magnify(with event: NSEvent) {
        guard let scroll = enclosingScrollView else { return }
        let target = Self.clampedZoom(
            current: scroll.magnification,
            factor: 1 + event.magnification,
            min: scroll.minMagnification,
            max: scroll.maxMagnification
        )
        let center = convert(event.locationInWindow, from: nil)
        scroll.setMagnification(target, centeredAt: center)
    }

    // MARK: - Mouse-wheel zoom

    /// Scroll-wheel / trackpad behaviour on the canvas:
    ///   • ⌘ + scroll → zoom, centered on the cursor.
    ///   • bare scroll → **pan** the canvas (translate the clip origin), the
    ///     same grab-the-canvas feel as drag-to-pan. We drive the clip
    ///     directly instead of letting NSScrollView scroll so there's no
    ///     rubber-band / overlay-scrollbar "scroll view" UX — just panning.
    public override func scrollWheel(with event: NSEvent) {
        guard let scroll = enclosingScrollView else {
            super.scrollWheel(with: event)
            return
        }
        if event.modifierFlags.contains(.command) {
            let factor = Self.scrollZoomFactor(delta: event.scrollingDeltaY)
            guard factor != 1 else { return }
            let target = Self.clampedZoom(
                current: scroll.magnification, factor: factor,
                min: scroll.minMagnification, max: scroll.maxMagnification)
            let center = convert(event.locationInWindow, from: nil)
            scroll.setMagnification(target, centeredAt: center)
            return
        }
        // No momentum/inertial panning. After the fingers lift, a trackpad keeps
        // emitting scrollWheel events with a non-empty momentumPhase — applying
        // those is what gives the "flung canvas" feel. Drop them; pan only while
        // the user is actively scrolling.
        if !event.momentumPhase.isEmpty { return }
        // Let NSScrollView do the actual scrolling. The previous hand-rolled
        // `origin -= delta` got the vertical sign wrong under "natural"
        // scrolling — scrolling down pinned the view at the top and it couldn't
        // come back ("locked"). Native scrolling already handles direction,
        // natural-scroll, precise vs line deltas and 2D/shift correctly, and
        // CanvasClipView.constrainBoundsRect still supplies the free-pan bounds
        // (that's the documented extension point). We only kill momentum above.
        super.scrollWheel(with: event)
    }


    /// Per-event zoom factor for ⌘+scroll: scroll up (positive delta) zooms in,
    /// down zooms out, each tick capped to ±20% so a chunky mouse wheel can't
    /// leap across the whole zoom range in one notch. Pure → unit-testable.
    static func scrollZoomFactor(delta: CGFloat) -> CGFloat {
        guard delta != 0 else { return 1 }
        let step = max(-0.2, min(0.2, delta * 0.01))
        return 1 + step
    }

}
