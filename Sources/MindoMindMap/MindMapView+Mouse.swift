import AppKit
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
        // Embedded-image hit: open the lightbox at full resolution.
        if event.clickCount >= 1, let image = embeddedImage(at: p) {
            MindMapImageLightbox.present(image: image, near: window)
            return
        }
        let el = element(at: p)
        // Cmd-click toggles multi-selection, Shift-click adds; otherwise replace.
        if event.modifierFlags.contains(.command) {
            toggleSelection(el)
        } else if event.modifierFlags.contains(.shift) {
            if let el = el {
                selectedTopics.insert(ObjectIdentifier(el.topic))
                selectedElement = el
                needsDisplay = true
            }
        } else {
            selectElement(el)
        }
        if event.clickCount == 2, let el = el {
            beginInlineEdit(on: el)
        } else if let el = el, el.topic.parent != nil,
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
        guard let origin = dragOrigin, let source = dragSourceElement else { return }
        let p = convert(event.locationInWindow, from: nil)
        if dragGhostCenter == nil {
            // Wait until we move past the threshold before showing the ghost.
            if hypot(p.x - origin.x, p.y - origin.y) < dragThreshold { return }
        }
        dragGhostCenter = p
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

    public override func mouseUp(with event: NSEvent) {
        if panOriginInWindow != nil {
            panOriginInWindow = nil
            panStartScroll = nil
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
        guard let target = dragTargetElement,
              target.topic !== source.topic.parent else { return }
        let index = target.topic.children.count
        undoableReparent(source.topic, to: target.topic, at: index)
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

        // Map gap (in sortedSiblings space) → insertion index in
        // parent.children (which can include the source itself + other-side
        // children, neither of which appear in `siblings`).
        // Find the children-array index of the sibling we're inserting *before*.
        let insertBefore: MindMapElement? = gap < sortedSiblings.count ? sortedSiblings[gap] : nil
        let insertIndex: Int
        if let target = insertBefore,
           let idx = parentEl.children.firstIndex(where: { $0 === target }) {
            insertIndex = idx
        } else {
            insertIndex = parentEl.children.count
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
