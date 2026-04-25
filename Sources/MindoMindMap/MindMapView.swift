import AppKit
import MindoModel

/// AppKit canvas that renders a mind map and handles mouse + keyboard editing.
/// Mirrors a small slice of `mindmap-panel`'s `MindMapPanel`/`MindMapViewSkin`.
public final class MindMapView: NSView {
    public var theme: MindMapTheme = .light {
        didSet { needsDisplay = true }
    }

    public private(set) var mindMap: MindMap?
    public private(set) var rootElement: MindMapElement?
    public private(set) var selectedElement: MindMapElement?

    /// Topics participating in a multi-selection. The "primary" topic
    /// (`selectedElement`) is also a member; the set is what actions like
    /// Delete operate on.
    public private(set) var selectedTopics: Set<ObjectIdentifier> = []

    /// Optional injected undo manager. When set, takes precedence over the
    /// responder-chain default (`super.undoManager`). Useful for tests and for
    /// callers that want a per-document undo stack.
    public var injectedUndoManager: UndoManager?

    public override var undoManager: UndoManager? {
        injectedUndoManager ?? super.undoManager
    }

    /// Called whenever the mind map mutates. UI layer can persist or mark dirty.
    public var onChange: ((MindMap) -> Void)?

    /// Called when the user clicks an `ExtraFile` icon. The app delegate
    /// resolves the path and opens the corresponding workspace file.
    public var onExtraFileTap: ((URL) -> Void)?

    /// Called when the user clicks an `ExtraTopic` jump-link icon — receives
    /// the target topic UID. The app may center the canvas on the destination.
    public var onExtraTopicTap: ((String) -> Void)?

    /// Optional override for note display (NSAlert by default).
    public var onExtraNoteTap: ((Topic, String) -> Void)?

    private var layoutEngine: MindMapLayout
    private var contentBounds: CGRect = .zero
    private var inlineEditor: NSTextField?

    // Drag-to-reparent state. `dragOrigin` arms the gesture on mouseDown; we
    // only commit to a drag once the cursor moves more than `dragThreshold`
    // away. `dragGhostCenter` and `dragTargetElement` drive the ghost +
    // highlighted drop-target rendering inside `draw(_:)`.
    private var dragOrigin: CGPoint?
    private var dragSourceElement: MindMapElement?
    private var dragGhostCenter: CGPoint?
    private var dragTargetElement: MindMapElement?
    private let dragThreshold: CGFloat = 4

    /// Pan state — entered when the user holds space and drags. Distinct from
    /// the topic-drag-to-reparent state above so a paused space-drag doesn't
    /// accidentally pick up a topic.
    private var isSpaceDown: Bool = false
    private var panOriginInWindow: CGPoint?
    private var panStartScroll: CGPoint?

    // MARK: - Init

    public override init(frame frameRect: NSRect) {
        self.layoutEngine = MindMapLayout(theme: .light)
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        self.layoutEngine = MindMapLayout(theme: .light)
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = theme.paperColor.cgColor
    }

    public override var acceptsFirstResponder: Bool { true }
    public override var isFlipped: Bool { true }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Eat key equivalents for keys we want `keyDown(with:)` to handle —
    /// otherwise NSWindow can grab Tab (focus traversal) or arrow keys
    /// (default key-loop) before they reach us. Returning `false` here
    /// signals the system to fall back to keyDown for non-equivalent keys.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Anything we explicitly handle in keyDown should NOT be intercepted
        // by the window's key-equivalent loop.
        let chars = event.charactersIgnoringModifiers ?? ""
        let arrows: Set<String> = [
            String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)),
            String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)),
            String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)),
            String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)),
        ]
        if window?.firstResponder === self,
           ["\t", "\r", "-", "=", "+", " "].contains(chars) || arrows.contains(chars) {
            self.keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Public API

    public func display(map: MindMap) {
        self.mindMap = map
        rebuildElements()
        // Auto-select root so the very first arrow / Tab / Enter has a
        // target without requiring a click first. Without this the user has
        // to click a topic before the keyboard does anything (bug #36).
        if let root = rootElement {
            selectElement(root)
        }
        needsDisplay = true
        // Try to grab focus on the next runloop pass so any sidebar List
        // that's currently first responder gives way once the canvas appears.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    /// Called by the SwiftUI bridge whenever the canvas is shown / re-shown.
    /// Idempotent.
    public func grabFocus() {
        window?.makeFirstResponder(self)
    }

    /// Local NSEvent monitor token. While installed, we intercept key
    /// events that should drive the canvas even when the SwiftUI sidebar
    /// list still holds first responder. Removed in `viewWillMove(toWindow:)`
    /// when leaving a window so we don't keep eating events for an
    /// off-screen view.
    private var keyMonitor: Any?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installKeyMonitor()
            installClipResizeWatcher()
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        } else {
            removeKeyMonitor()
            removeClipResizeWatcher()
        }
    }

    private func installClipResizeWatcher() {
        guard let scroll = enclosingScrollView else { return }
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewDidResize(_:)),
            name: NSView.frameDidChangeNotification, object: scroll.contentView
        )
    }

    private func removeClipResizeWatcher() {
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { removeKeyMonitor() }
    }

    deinit { Self.removeMonitor(keyMonitor) }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        // Catch only the keys the canvas actually drives. Anything else
        // (typing into a text field, ⌘shortcuts, etc.) flows through
        // unchanged. Returning the event passes it on; nil swallows it.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, let win = self.window, event.window === win else { return event }
            // Skip if a text editor (in-place edit, TextField, etc.) is the
            // current responder — those should keep their typing behavior.
            if let responder = win.firstResponder,
               responder is NSText || responder is NSTextField || responder is NSTextView {
                return event
            }
            let chars = event.charactersIgnoringModifiers ?? ""
            let arrows: Set<String> = [
                String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)),
                String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)),
                String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)),
                String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)),
            ]
            let driven: Set<String> = ["\t", "\r", "-", "=", "+", " ", "\u{7F}", "\u{08}"]
            guard driven.contains(chars) || arrows.contains(chars) else { return event }
            // Make sure this canvas is actually visible in the window before
            // claiming the key — otherwise we'd silently swallow events for
            // closed tabs (the AppSession recreates MindMapViews per doc).
            guard self.window?.contentView?.subviewIsVisible(self) ?? false else { return event }
            if event.type == .keyDown {
                self.keyDown(with: event)
            } else {
                self.keyUp(with: event)
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        Self.removeMonitor(keyMonitor)
        keyMonitor = nil
    }

    private static func removeMonitor(_ monitor: Any?) {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }

    /// Public hook for the undo extension. Same as `rebuildElements()`.
    public func rebuildElementsPublic() {
        rebuildElements()
    }

    private func rebuildElements() {
        guard let root = mindMap?.root else { rootElement = nil; return }
        rootElement = MindMapElement.build(from: root)
        relayout()
    }

    private func relayout() {
        guard let root = rootElement else { return }
        layoutEngine = MindMapLayout(theme: theme)
        let bounds = layoutEngine.layout(root)
        contentBounds = bounds

        // Translate so all coordinates are positive. We do this by shifting frames
        // by `-bounds.origin`.
        let dx = -bounds.origin.x
        let dy = -bounds.origin.y
        root.traverse { el in
            el.frame.origin.x += dx
            el.frame.origin.y += dy
            el.subtreeBounds.origin.x += dx
            el.subtreeBounds.origin.y += dy
        }
        contentBounds.origin = .zero

        // Floor the document view to the scroll view's visible area so the
        // canvas always fills the container — even when the topic content is
        // tiny. Without this we'd shrink to (contentBounds + 64) and leave
        // dead space on the right/bottom (bug #38).
        let visibleSize = enclosingScrollView?.contentView.bounds.size ?? bounds.size
        let minWidth = max(visibleSize.width, contentBounds.width + 64)
        let minHeight = max(visibleSize.height, contentBounds.height + 64)
        if let parent = enclosingScrollView {
            self.frame = CGRect(x: 0, y: 0, width: minWidth, height: minHeight)
            parent.documentView?.frame.size = CGSize(width: minWidth, height: minHeight)
        } else {
            self.frame.size = CGSize(width: minWidth, height: minHeight)
        }
        needsDisplay = true
    }

    /// Re-run layout whenever the enclosing scroll view's clip area changes
    /// size — keeps the document view filling the viewport on window resize.
    @objc private func clipViewDidResize(_ note: Notification) {
        relayout()
    }

    // MARK: - Hit testing

    public func element(at point: CGPoint) -> MindMapElement? {
        guard let root = rootElement else { return nil }
        var hit: MindMapElement? = nil
        root.traverse { el in
            if el.frame.insetBy(dx: -2, dy: -2).contains(point) { hit = el }
        }
        return hit
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(theme.paperColor.cgColor)
        ctx.fill(bounds)

        guard let root = rootElement else { return }

        // Connectors first (under the rectangles).
        ctx.setStrokeColor(theme.connectorColor.cgColor)
        ctx.setLineWidth(theme.connectorWidth)
        drawConnectors(from: root, into: ctx)

        // Then topic rectangles + text.
        root.traverse { el in
            drawElement(el, into: ctx)
        }

        // Jump arrows for ExtraTopic links — drawn over the topics so they're
        // visible above shadow + fill.
        drawJumpArrows(rootElement: root, into: ctx)

        // Selection overlay on top — secondary members of the multi-selection
        // first (lighter), primary on top.
        if !selectedTopics.isEmpty, let root = rootElement {
            let secondary = theme.selectionColor.withAlphaComponent(0.45)
            ctx.setLineWidth(max(1, theme.selectionWidth - 0.5))
            root.traverse { el in
                guard selectedTopics.contains(ObjectIdentifier(el.topic)) else { return }
                if el === selectedElement { return }
                ctx.setStrokeColor(secondary.cgColor)
                let rect = el.frame.insetBy(dx: -2, dy: -2)
                let path = CGPath(roundedRect: rect, cornerWidth: theme.cornerRadius + 2, cornerHeight: theme.cornerRadius + 2, transform: nil)
                ctx.addPath(path); ctx.strokePath()
            }
        }
        if let sel = selectedElement {
            ctx.setStrokeColor(theme.selectionColor.cgColor)
            ctx.setLineWidth(theme.selectionWidth)
            let rect = sel.frame.insetBy(dx: -3, dy: -3)
            let path = CGPath(roundedRect: rect, cornerWidth: theme.cornerRadius + 3, cornerHeight: theme.cornerRadius + 3, transform: nil)
            ctx.addPath(path)
            ctx.strokePath()
        }

        // Drag overlays — drop-target highlight + dragged-topic ghost.
        if let target = dragTargetElement {
            ctx.setStrokeColor(NSColor.systemGreen.cgColor)
            ctx.setLineWidth(2.0)
            let rect = target.frame.insetBy(dx: -5, dy: -5)
            let path = CGPath(roundedRect: rect, cornerWidth: theme.cornerRadius + 5, cornerHeight: theme.cornerRadius + 5, transform: nil)
            ctx.addPath(path)
            ctx.strokePath()
        }
        if let center = dragGhostCenter, let source = dragSourceElement {
            let size = source.frame.size
            let rect = CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width, height: size.height
            )
            ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.18).cgColor)
            let path = CGPath(roundedRect: rect, cornerWidth: theme.cornerRadius, cornerHeight: theme.cornerRadius, transform: nil)
            ctx.addPath(path); ctx.fillPath()
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(path); ctx.strokePath()
        }
    }

    private func drawElement(_ el: MindMapElement, into ctx: CGContext) {
        let level = el.level
        let path = CGPath(
            roundedRect: el.frame,
            cornerWidth: theme.cornerRadius,
            cornerHeight: theme.cornerRadius,
            transform: nil
        )

        // Drop shadow (skip on root which is filled solid).
        if level > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: theme.dropShadowOffset, blur: 4, color: NSColor.black.withAlphaComponent(theme.dropShadowOpacity).cgColor)
            ctx.addPath(path)
            ctx.setFillColor(theme.fillColor(forLevel: level).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        } else {
            ctx.addPath(path)
            ctx.setFillColor(theme.fillColor(forLevel: level).cgColor)
            ctx.fillPath()
        }

        // Border.
        ctx.addPath(path)
        ctx.setStrokeColor(theme.borderColor(forLevel: level).cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokePath()

        // Embedded image (above the text).
        if let image = el.embeddedImage {
            let imageRect = el.embeddedImageDrawRect
            ctx.saveGState()
            ctx.interpolationQuality = .high
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
            ctx.restoreGState()
        }

        // Text — leaves room on the right for the extra-icons strip.
        let font = theme.font(forLevel: level)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.textColor(forLevel: level),
            .paragraphStyle: style,
        ]
        var textRect = el.frame.insetBy(dx: theme.textInsets.left, dy: theme.textInsets.top)
        if el.extraIconStripWidth > 0 {
            textRect.size.width = max(0, textRect.width - el.extraIconStripWidth)
        }
        if el.embeddedImageHeight > 0 {
            textRect.origin.y += el.embeddedImageHeight
            textRect.size.height = max(0, textRect.height - el.embeddedImageHeight)
        }
        let displayText = el.topic.text.isEmpty ? "·" : el.topic.text
        (displayText as NSString).draw(in: textRect, withAttributes: attrs)

        // Extras strip.
        for (type, rect) in el.extraIconRects {
            drawExtraIcon(type: type, in: rect, level: level, into: ctx)
        }

        // Collapse marker (small caret on the side facing children).
        if el.isCollapsed && !el.children.isEmpty {
            let marker = "+"
            let mAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 10),
                .foregroundColor: theme.borderColor(forLevel: level),
            ]
            let size = (marker as NSString).size(withAttributes: mAttrs)
            let x = el.isLeftSide ? el.frame.minX - size.width - 4 : el.frame.maxX + 4
            (marker as NSString).draw(at: CGPoint(x: x, y: el.frame.midY - size.height / 2), withAttributes: mAttrs)
        }
    }

    private func drawConnectors(from element: MindMapElement, into ctx: CGContext) {
        if element.level == 0, let root = rootElement, root === element {
            for child in root.leftChildren { drawConnector(from: root, to: child, into: ctx); drawConnectors(from: child, into: ctx) }
            for child in root.rightChildren { drawConnector(from: root, to: child, into: ctx); drawConnectors(from: child, into: ctx) }
            return
        }
        guard !element.isCollapsed else { return }
        for child in element.children {
            drawConnector(from: element, to: child, into: ctx)
            drawConnectors(from: child, into: ctx)
        }
    }

    /// Render an SF Symbol-based icon for one extra type inside `rect`.
    private func drawExtraIcon(type: ExtraType, in rect: CGRect, level: Int, into ctx: CGContext) {
        let symbolName: String
        switch type {
        case .note:  symbolName = "note.text"
        case .link:  symbolName = "link"
        case .file:  symbolName = "paperclip"
        case .topic: symbolName = "arrow.uturn.right.circle"
        case .unknown: symbolName = "questionmark.circle"
        }
        let config = NSImage.SymbolConfiguration(pointSize: rect.width - 2, weight: .medium)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let tint = theme.textColor(forLevel: level).withAlphaComponent(0.85)
        let tinted = image.copy() as! NSImage
        tinted.lockFocus()
        tint.set()
        let imageRect = NSRect(origin: .zero, size: tinted.size)
        imageRect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        let drawRect = CGRect(
            x: rect.midX - tinted.size.width / 2,
            y: rect.midY - tinted.size.height / 2,
            width: tinted.size.width, height: tinted.size.height
        )
        tinted.draw(in: drawRect)
    }

    /// Draw a dashed cubic-bezier arrow for every topic that has an
    /// ExtraTopic pointing to another topic in the same map. Mirrors
    /// `mindmap-panel`'s "jump" overlay.
    private func drawJumpArrows(rootElement: MindMapElement, into ctx: CGContext) {
        guard let map = mindMap else { return }
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.setStrokeColor(NSColor.systemPurple.withAlphaComponent(0.85).cgColor)
        ctx.setFillColor(NSColor.systemPurple.cgColor)
        ctx.setLineWidth(1.2)
        rootElement.traverse { el in
            guard let extra = el.topic.extra(.topic) as? ExtraTopic,
                  let target = map.findTopic(uid: extra.value),
                  let targetEl = element(forTopic: target) else { return }
            drawJumpArrow(from: el, to: targetEl, into: ctx)
        }
        ctx.restoreGState()
    }

    private func drawJumpArrow(from a: MindMapElement, to b: MindMapElement, into ctx: CGContext) {
        let start = CGPoint(x: a.frame.midX, y: a.frame.midY)
        let end = CGPoint(x: b.frame.midX, y: b.frame.midY)
        // Anchor the line on the box edges so it doesn't disappear under the
        // topic rects.
        let p1 = clip(point: start, against: a.frame, towards: end)
        let p2 = clip(point: end, against: b.frame, towards: start)
        let dx = p2.x - p1.x, dy = p2.y - p1.y
        // Bow the arc out by 30% of the chord length so curves don't overlap
        // straight connectors.
        let bowOffset = max(28, hypot(dx, dy) * 0.30)
        let cx = (p1.x + p2.x) / 2 + (-dy / hypot(dx, dy)) * bowOffset
        let cy = (p1.y + p2.y) / 2 + (dx / hypot(dx, dy)) * bowOffset

        ctx.beginPath()
        ctx.move(to: p1)
        ctx.addQuadCurve(to: p2, control: CGPoint(x: cx, y: cy))
        ctx.strokePath()

        // Arrow head at p2.
        let head: CGFloat = 9
        let angle = atan2(p2.y - cy, p2.x - cx)
        let h1 = CGPoint(x: p2.x - head * cos(angle - .pi / 6), y: p2.y - head * sin(angle - .pi / 6))
        let h2 = CGPoint(x: p2.x - head * cos(angle + .pi / 6), y: p2.y - head * sin(angle + .pi / 6))
        ctx.beginPath()
        ctx.move(to: p2); ctx.addLine(to: h1); ctx.addLine(to: h2); ctx.closePath()
        ctx.fillPath()
    }

    /// Clip a line endpoint to the rectangle's edge along the line towards `away`.
    private func clip(point: CGPoint, against rect: CGRect, towards away: CGPoint) -> CGPoint {
        let dx = away.x - point.x, dy = away.y - point.y
        guard dx != 0 || dy != 0 else { return point }
        let length = hypot(dx, dy)
        let nx = dx / length, ny = dy / length
        // Step out along the direction until we leave the rect.
        var t: CGFloat = 0
        let step: CGFloat = 1
        while t < length, rect.contains(CGPoint(x: point.x + nx * t, y: point.y + ny * t)) {
            t += step
        }
        return CGPoint(x: point.x + nx * t, y: point.y + ny * t)
    }

    private func drawConnector(from parent: MindMapElement, to child: MindMapElement, into ctx: CGContext) {
        // Start at the parent edge facing the child; end at the child edge facing the parent.
        let pStart: CGPoint
        let pEnd: CGPoint
        if child.isLeftSide {
            pStart = CGPoint(x: parent.frame.minX, y: parent.frame.midY)
            pEnd = CGPoint(x: child.frame.maxX, y: child.frame.midY)
        } else {
            pStart = CGPoint(x: parent.frame.maxX, y: parent.frame.midY)
            pEnd = CGPoint(x: child.frame.minX, y: child.frame.midY)
        }
        let midX = (pStart.x + pEnd.x) / 2
        let c1 = CGPoint(x: midX, y: pStart.y)
        let c2 = CGPoint(x: midX, y: pEnd.y)

        ctx.beginPath()
        ctx.move(to: pStart)
        ctx.addCurve(to: pEnd, control1: c1, control2: c2)
        ctx.setStrokeColor(theme.connectorColor.cgColor)
        ctx.strokePath()
    }

    // MARK: - Mouse

    public override func rightMouseDown(with event: NSEvent) {
        commitInlineEdit()
        let p = convert(event.locationInWindow, from: nil)
        guard let element = element(at: p) else { return }
        select(element)
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
            select(el)
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

    /// Find the (element, extra-type) under `point`. Returns nil when no
    /// extra icon is hit.
    private func elementExtra(at point: CGPoint) -> (MindMapElement, ExtraType)? {
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

    private func handleExtraTap(on element: MindMapElement, type: ExtraType) {
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

    private func showNoteAlert(text: String) {
        let alert = NSAlert()
        alert.messageText = "Note"
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        if let moved = element(for: source.topic) { select(moved) }
    }

    private func resetDragState() {
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
    private func candidateDropTarget(under point: CGPoint, excluding source: MindMapElement) -> MindMapElement? {
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

    // MARK: - Keyboard

    public override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else { super.keyDown(with: event); return }
        let isShift = event.modifierFlags.contains(.shift)

        if chars == " " {
            if !isSpaceDown {
                isSpaceDown = true
                NSCursor.openHand.push()
            }
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
        case String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)):
            isShift ? extendSelection(.left) : move(.left)
        case String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)):
            isShift ? extendSelection(.right) : move(.right)
        case String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)):
            isShift ? extendSelection(.up) : move(.up)
        case String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)):
            isShift ? extendSelection(.down) : move(.down)
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

    /// Zoom math exposed for unit tests — clamps to a bounded range and snaps
    /// to the supplied factor.
    public static func clampedZoom(current: CGFloat, factor: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        return Swift.max(lower, Swift.min(upper, current * factor))
    }

    enum Direction { case left, right, up, down }

    /// Resolve the topic in `direction` of `from`. Used by both the single-
    /// select arrow handler and the multi-select extender.
    func element(in direction: Direction, of from: MindMapElement) -> MindMapElement? {
        guard let root = rootElement else { return nil }
        switch direction {
        case .right:
            if let target = from.children.first(where: { !$0.isLeftSide }) ?? from.children.first { return target }
            if from === root { return root.rightChildren.first }
        case .left:
            if let target = from.children.first(where: { $0.isLeftSide }) { return target }
            if from === root { return root.leftChildren.first }
            if let parent = from.topic.parent, let parentEl = element(forTopic: parent) { return parentEl }
        case .up, .down:
            guard let parent = from.topic.parent, let parentEl = element(forTopic: parent) else { return nil }
            let siblings = parentEl.children.filter { $0.isLeftSide == from.isLeftSide }
            if let idx = siblings.firstIndex(where: { $0 === from }) {
                let next = direction == .up ? idx - 1 : idx + 1
                if siblings.indices.contains(next) { return siblings[next] }
            }
        }
        return nil
    }

    private func move(_ direction: Direction) {
        guard let sel = selectedElement, let target = element(in: direction, of: sel) else { return }
        select(target)
    }

    /// Internal — extensions in this module need to map a `Topic` back to its
    /// `MindMapElement` for selection / navigation.
    func element(forTopic topic: Topic) -> MindMapElement? {
        var found: MindMapElement?
        rootElement?.traverse { if $0.topic === topic { found = $0 } }
        return found
    }

    private func element(for topic: Topic) -> MindMapElement? { element(forTopic: topic) }

    // MARK: - Edits

    /// Internal so extensions in the same module (navigation, undo) can drive
    /// selection. Renamed away from BSD `select(2)`'s naming so the navigation
    /// extension doesn't accidentally bind to the C function.
    ///
    /// Single-selection: replaces the set with just `element`. Use
    /// `toggleSelection` or `extendSelection` for multi-select gestures.
    func selectElement(_ element: MindMapElement?) {
        selectedElement = element
        if let el = element {
            selectedTopics = [ObjectIdentifier(el.topic)]
            scrollToVisible(el.frame.insetBy(dx: -32, dy: -32))
        } else {
            selectedTopics.removeAll()
        }
        needsDisplay = true
    }

    /// Cmd-click — toggle membership without disturbing the primary selection.
    /// Promotes the toggled topic to primary when adding.
    func toggleSelection(_ element: MindMapElement?) {
        guard let el = element else { return }
        let id = ObjectIdentifier(el.topic)
        if selectedTopics.contains(id) {
            selectedTopics.remove(id)
            // If we just removed the primary, fall back to any remaining one.
            if selectedElement?.topic === el.topic {
                selectedElement = anyOtherSelectedElement(excluding: el)
            }
        } else {
            selectedTopics.insert(id)
            selectedElement = el
        }
        needsDisplay = true
    }

    /// Shift+arrow — extend the selection by adding the topic in `direction`
    /// of the primary element to the set, then promote it to primary.
    func extendSelection(_ direction: Direction) {
        guard let primary = selectedElement,
              let target = element(in: direction, of: primary) else { return }
        selectedTopics.insert(ObjectIdentifier(primary.topic))
        selectedTopics.insert(ObjectIdentifier(target.topic))
        selectedElement = target
        scrollToVisible(target.frame.insetBy(dx: -32, dy: -32))
        needsDisplay = true
    }

    private func anyOtherSelectedElement(excluding ignored: MindMapElement) -> MindMapElement? {
        guard let root = rootElement else { return nil }
        var found: MindMapElement?
        root.traverse { el in
            if found == nil, el !== ignored, selectedTopics.contains(ObjectIdentifier(el.topic)) {
                found = el
            }
        }
        return found
    }

    private func select(_ element: MindMapElement?) { selectElement(element) }

    private func toggleCollapse(toCollapsed: Bool) {
        guard let sel = selectedElement, !sel.children.isEmpty else { return }
        undoableSetAttribute(sel.topic, key: TopicAttribute.collapsed, value: toCollapsed ? "true" : nil)
    }

    private func addChild() {
        guard let sel = selectedElement else {
            if let root = mindMap?.root {
                let child = undoableAddChild(to: root, text: "Topic")
                if let el = element(for: child) { select(el); beginInlineEdit(on: el) }
            }
            return
        }
        let child = undoableAddChild(to: sel.topic, text: "Topic")
        if let el = element(for: child) { select(el); beginInlineEdit(on: el) }
    }

    private func addNextSibling() {
        guard let sel = selectedElement, let parent = sel.topic.parent else { addChild(); return }
        let new = undoableAddChild(to: parent, text: "Topic")
        if let el = element(for: new) { select(el); beginInlineEdit(on: el) }
    }

    private func addPreviousSibling() {
        guard let sel = selectedElement, let parent = sel.topic.parent else { addChild(); return }
        let target = sel.topic
        let new = undoableAddChild(to: parent, text: "Topic")
        if let idx = parent.children.firstIndex(where: { $0 === target }) {
            parent.move(child: new, to: idx)
            rebuildElementsPublic()
        }
        if let el = element(for: new) { select(el); beginInlineEdit(on: el) }
    }

    private func deleteSelection() {
        // Multi-select aware: collect every selected non-root topic, walk
        // outermost-children-first so removing one doesn't invalidate the
        // others' parent pointers.
        guard let root = rootElement else { return }
        var victims: [Topic] = []
        root.traverse { el in
            if el.topic.parent != nil, selectedTopics.contains(ObjectIdentifier(el.topic)) {
                victims.append(el.topic)
            }
        }
        // De-dupe: drop any victim that's a descendant of another victim, the
        // ancestor's removal already takes care of it.
        let descendants = Set(victims.map(ObjectIdentifier.init))
        let pruned = victims.filter { topic in
            var t: Topic? = topic.parent
            while let cur = t {
                if descendants.contains(ObjectIdentifier(cur)) { return false }
                t = cur.parent
            }
            return true
        }
        guard !pruned.isEmpty else { return }
        for topic in pruned {
            undoableRemove(topic)
        }
        // Selection collapses to the first surviving parent.
        if let firstParent = pruned.first?.parent, let parentEl = element(forTopic: firstParent) {
            select(parentEl)
        }
    }

    // MARK: - Inline edit

    private func beginInlineEdit(on element: MindMapElement) {
        let textField = NSTextField(frame: element.frame)
        textField.stringValue = element.topic.text
        textField.font = theme.font(forLevel: element.level)
        textField.alignment = .center
        textField.bezelStyle = .roundedBezel
        textField.target = self
        textField.action = #selector(commitInlineEdit)
        addSubview(textField)
        window?.makeFirstResponder(textField)
        inlineEditor = textField
    }

    @objc private func commitInlineEdit() {
        guard let editor = inlineEditor, let sel = selectedElement else { return }
        let newText = editor.stringValue
        editor.removeFromSuperview()
        inlineEditor = nil
        undoableSetText(sel.topic, to: newText)
        window?.makeFirstResponder(self)
    }

    private func notifyChange() {
        if let map = mindMap { onChange?(map) }
    }
}

private extension NSView {
    /// True when `target` lives in this view's hierarchy and is rendered.
    /// Used by the key monitor to skip canvases for closed/hidden tabs.
    func subviewIsVisible(_ target: NSView) -> Bool {
        if target === self { return !isHidden && window != nil }
        for sub in subviews where sub.subviewIsVisible(target) {
            return true
        }
        return false
    }
}

// MARK: - Topic helper for in-place reorder

extension Topic {
    /// Move `child` (which must already be in `children`) to the given index.
    func move(child: Topic, to index: Int) {
        guard let from = children.firstIndex(where: { $0 === child }) else { return }
        let to = max(0, min(index, children.count - 1))
        if from == to { return }
        // `children` is private(set); use the addChild/removeChild API to mutate.
        // We rebuild the list in the desired order.
        var arr = children
        let moving = arr.remove(at: from)
        arr.insert(moving, at: to)
        replaceChildren(arr)
    }

    private func replaceChildren(_ ordered: [Topic]) {
        // Mirror the array using public mutators: clear and re-append.
        let snapshot = children
        for c in snapshot { removeChild(c) }
        for c in ordered { append(c) }
    }
}
