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
    public internal(set) var selectedElement: MindMapElement?

    /// Topics participating in a multi-selection. The "primary" topic
    /// (`selectedElement`) is also a member; the set is what actions like
    /// Delete operate on.
    public internal(set) var selectedTopics: Set<ObjectIdentifier> = []

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
    /// File-internal so MindMapView+Mouse / +Keyboard extensions in this
    /// module can read + reset the inline edit field.
    var inlineEditor: NSTextField?

    // Drag-to-reparent state. `dragOrigin` arms the gesture on mouseDown; we
    // only commit to a drag once the cursor moves more than `dragThreshold`
    // away. `dragGhostCenter` and `dragTargetElement` drive the ghost +
    // highlighted drop-target rendering inside `draw(_:)`. All file-internal
    // because the +Mouse extension lives in a separate file.
    var dragOrigin: CGPoint?
    var dragSourceElement: MindMapElement?
    var dragGhostCenter: CGPoint?
    var dragTargetElement: MindMapElement?
    let dragThreshold: CGFloat = 4

    /// Pan state — entered when the user holds space and drags. Distinct from
    /// the topic-drag-to-reparent state above so a paused space-drag doesn't
    /// accidentally pick up a topic.
    var isSpaceDown: Bool = false
    var panOriginInWindow: CGPoint?
    var panStartScroll: CGPoint?

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

    // Drawing helpers (drawElement, drawConnectors, drawConnector,
    // drawExtraIcon, drawJumpArrows, drawJumpArrow, clip) live in
    // MindMapView+Drawing.swift to keep this file focused on state +
    // event handling.


    // MARK: - Keyboard


    enum Direction { case left, right, up, down }

    /// Resolve the topic in `direction` of `from`. Used by both the single-
    /// select arrow handler and the multi-select extender.

    /// Internal — extensions in this module need to map a `Topic` back to its
    /// `MindMapElement` for selection / navigation.
    func element(forTopic topic: Topic) -> MindMapElement? {
        var found: MindMapElement?
        rootElement?.traverse { if $0.topic === topic { found = $0 } }
        return found
    }


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

    func toggleCollapse(toCollapsed: Bool) {
        guard let sel = selectedElement, !sel.children.isEmpty else { return }
        undoableSetAttribute(sel.topic, key: TopicAttribute.collapsed, value: toCollapsed ? "true" : nil)
    }

    func addChild() {
        guard let sel = selectedElement else {
            if let root = mindMap?.root {
                let child = undoableAddChild(to: root, text: "Topic")
                if let el = element(forTopic: child) { selectElement(el); beginInlineEdit(on: el) }
            }
            return
        }
        let child = undoableAddChild(to: sel.topic, text: "Topic")
        if let el = element(forTopic: child) { selectElement(el); beginInlineEdit(on: el) }
    }

    func addNextSibling() {
        guard let sel = selectedElement, let parent = sel.topic.parent else { addChild(); return }
        let new = undoableAddChild(to: parent, text: "Topic")
        if let el = element(forTopic: new) { selectElement(el); beginInlineEdit(on: el) }
    }

    func addPreviousSibling() {
        guard let sel = selectedElement, let parent = sel.topic.parent else { addChild(); return }
        let target = sel.topic
        let new = undoableAddChild(to: parent, text: "Topic")
        if let idx = parent.children.firstIndex(where: { $0 === target }) {
            parent.move(child: new, to: idx)
            rebuildElementsPublic()
        }
        if let el = element(forTopic: new) { selectElement(el); beginInlineEdit(on: el) }
    }

    func deleteSelection() {
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
            selectElement(parentEl)
        }
    }

    // MARK: - Inline edit

    func beginInlineEdit(on element: MindMapElement) {
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

    @objc func commitInlineEdit() {
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
