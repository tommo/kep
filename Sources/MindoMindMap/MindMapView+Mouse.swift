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
        let menu = makeContextMenu(for: element)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    public override func mouseDown(with event: NSEvent) {
        commitInlineEdit()
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
            scroll.contentView.scroll(to: target)
            scroll.reflectScrolledClipView(scroll.contentView)
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
        // Auto-scroll when the drag nears a viewport edge so off-screen drop
        // targets are reachable without releasing. Pure ramp math; applied to
        // the clip view here.
        autoScrollDuringDrag(cursor: p)
        // "Drop between siblings" wins over "drop onto topic" — when the
        // cursor lands in a gap among the source's existing siblings, show
        // the insertion indicator instead of highlighting a parent.
        if let ins = candidateInsertionTarget(under: p, source: source) {
            dragInsertionTarget = ins
            dragTargetElement = nil
        } else {
            dragInsertionTarget = nil
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
        if let ins = dragInsertionTarget {
            // Reorder among siblings — index already accounts for source's
            // current position via undoableReparent's remove-then-insert.
            undoableReparent(source.topic, to: ins.parent.topic, at: ins.index)
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
            needsDisplay = true
        }
        dragOrigin = nil
        dragSourceElement = nil
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
        guard let parentTopic = source.topic.parent,
              let parentEl = element(forTopic: parentTopic) else { return nil }
        let siblings = parentEl.children.filter { $0.isLeftSide == source.isLeftSide && $0 !== source }
        guard !siblings.isEmpty else { return nil }
        let sortedSiblings = siblings.sorted { $0.frame.minY < $1.frame.minY }
        let ranges = sortedSiblings.map { MindMapDragGap.YRange($0.frame.minY, $0.frame.maxY) }

        // Don't activate if the cursor is far outside the sibling X-band —
        // otherwise dragging across the canvas to reparent flickers.
        let minX = sortedSiblings.map(\.frame.minX).min() ?? 0
        let maxX = sortedSiblings.map(\.frame.maxX).max() ?? 0
        let hPad: CGFloat = 60
        guard p.x >= minX - hPad, p.x <= maxX + hPad else { return nil }

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
            onExtraTopicTap?(extra.value)
        case .note:
            if let custom = onExtraNoteTap {
                custom(element.topic, extra.value)
            } else {
                showNoteAlert(text: extra.value)
            }
        case .unknown:
            break
        }
    }

    func showNoteAlert(text: String) {
        let alert = NSAlert()
        alert.messageText = "Note"
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
}
