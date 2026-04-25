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
        dragTargetElement = candidateDropTarget(under: p, excluding: source)
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        if panOriginInWindow != nil {
            panOriginInWindow = nil
            panStartScroll = nil
            return
        }
        defer { resetDragState() }
        guard let source = dragSourceElement,
              dragGhostCenter != nil,
              let target = dragTargetElement,
              target.topic !== source.topic.parent else { return }
        let index = target.topic.children.count
        undoableReparent(source.topic, to: target.topic, at: index)
        if let moved = element(forTopic: source.topic) { selectElement(moved) }
    }

    func resetDragState() {
        if dragGhostCenter != nil || dragTargetElement != nil {
            dragGhostCenter = nil
            dragTargetElement = nil
            needsDisplay = true
        }
        dragOrigin = nil
        dragSourceElement = nil
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
}
