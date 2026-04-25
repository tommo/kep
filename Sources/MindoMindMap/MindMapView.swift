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
    var contentBounds: CGRect = .zero
    /// File-internal so MindMapView+Mouse / +Keyboard extensions in this
    /// module can read + reset the inline edit field.
    var inlineEditor: NSTextField?
    /// Topic the inlineEditor is currently editing. Set in beginInlineEdit
    /// so commitInlineEdit applies the text to the right node even when
    /// the selection moved on (e.g. Tab created a child mid-edit).
    var inlineEditTarget: Topic?

    // Drag-to-reparent state. `dragOrigin` arms the gesture on mouseDown; we
    // only commit to a drag once the cursor moves more than `dragThreshold`
    // away. `dragGhostCenter` and `dragTargetElement` drive the ghost +
    // highlighted drop-target rendering inside `draw(_:)`. All file-internal
    // because the +Mouse extension lives in a separate file.
    var dragOrigin: CGPoint?
    var dragSourceElement: MindMapElement?
    var dragGhostCenter: CGPoint?
    var dragTargetElement: MindMapElement?
    /// "Drop between siblings" target — a horizontal indicator line + the
    /// children-array index where the dragged topic should land. When set,
    /// it takes precedence over `dragTargetElement` on mouseUp.
    var dragInsertionTarget: (parent: MindMapElement, index: Int, lineY: CGFloat, lineMinX: CGFloat, lineMaxX: CGFloat)?
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

    /// Arrow-key string → navigation direction. Source of truth for both
    /// the gate sets in `performKeyEquivalent` / the NSEvent monitor and
    /// the dispatch table in `keyDown(with:)` so a future direction key
    /// only edits one place.
    static let arrowKeyDirections: [String: Direction] = [
        String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)): .left,
        String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)): .right,
        String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)): .up,
        String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)): .down,
    ]
    static var arrowKeyChars: Set<String> { Set(arrowKeyDirections.keys) }


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
            let driven: Set<String> = ["\t", "\r", "-", "=", "+", " ", "\u{7F}", "\u{08}"]
            guard driven.contains(chars) || Self.arrowKeyChars.contains(chars) else { return event }
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

        // First normalize so the content's top-left sits at (0, 0).
        shiftAllFrames(rootElement: root, dx: -bounds.origin.x, dy: -bounds.origin.y)
        contentBounds.origin = .zero

        // Floor the document view to the scroll view's visible area so the
        // canvas always fills the container — even when the topic content is
        // tiny (bug #38).
        let visibleSize = enclosingScrollView?.contentView.bounds.size ?? bounds.size
        let minWidth = max(visibleSize.width, contentBounds.width + 64)
        let minHeight = max(visibleSize.height, contentBounds.height + 64)
        if let parent = enclosingScrollView {
            self.frame = CGRect(x: 0, y: 0, width: minWidth, height: minHeight)
            parent.documentView?.frame.size = CGSize(width: minWidth, height: minHeight)
        } else {
            self.frame.size = CGSize(width: minWidth, height: minHeight)
        }

        // Then center the content inside the document view. Without this the
        // tree is glued to the top-left and the user sees a "canvas edge"
        // off to the right/bottom when content is smaller than the viewport
        // (bug #41). Centering also makes scroll-back-to-root predictable
        // — the root sits at the middle of the document area instead of
        // at (32, 32).
        let centerX = (minWidth - contentBounds.width) / 2
        let centerY = (minHeight - contentBounds.height) / 2
        shiftAllFrames(rootElement: root, dx: centerX, dy: centerY)
        contentBounds.origin = CGPoint(x: centerX, y: centerY)

        needsDisplay = true
    }

    /// Translate every element's frame + subtreeBounds by (dx, dy).
    private func shiftAllFrames(rootElement: MindMapElement, dx: CGFloat, dy: CGFloat) {
        guard dx != 0 || dy != 0 else { return }
        rootElement.traverse { el in
            el.frame.origin.x += dx
            el.frame.origin.y += dy
            el.subtreeBounds.origin.x += dx
            el.subtreeBounds.origin.y += dy
        }
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
                strokeRoundedOutline(around: el.frame, inset: 2, into: ctx)
            }
        }
        if let sel = selectedElement {
            ctx.setStrokeColor(theme.selectionColor.cgColor)
            ctx.setLineWidth(theme.selectionWidth)
            strokeRoundedOutline(around: sel.frame, inset: 3, into: ctx)
        }

        // Drag overlays — drop-target highlight + dragged-topic ghost.
        if let target = dragTargetElement {
            ctx.setStrokeColor(NSColor.systemGreen.cgColor)
            ctx.setLineWidth(2.0)
            strokeRoundedOutline(around: target.frame, inset: 5, into: ctx)
        }
        if let ins = dragInsertionTarget {
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(3.0)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: ins.lineMinX, y: ins.lineY))
            ctx.addLine(to: CGPoint(x: ins.lineMaxX, y: ins.lineY))
            ctx.strokePath()
            ctx.setLineCap(.butt)
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

    /// Fold (or unfold) every topic in the map in a single undoable step.
    /// Backs the Fold All / Unfold All menu commands.
    public func setAllCollapsed(_ collapsed: Bool) {
        undoableSetAllCollapsed(collapsed)
    }

    func addChild() {
        guard let sel = selectedElement else {
            if let root = mindMap?.root {
                selectAndEdit(undoableAddChild(to: root, text: "Topic"))
            }
            return
        }
        selectAndEdit(undoableAddChild(to: sel.topic, text: "Topic"))
    }

    func addNextSibling() {
        guard let sel = selectedElement, let parent = sel.topic.parent else { addChild(); return }
        let target = sel.topic
        let new = undoableAddChild(to: parent, text: "Topic")
        if let idx = parent.children.firstIndex(where: { $0 === target }) {
            // Insert *right after* the current sibling, not at the end of
            // the children list. Bug #40: addNextSibling used to append.
            parent.move(child: new, to: idx + 1)
            rebuildElementsPublic()
        }
        inheritRootSide(from: target, to: new)
        selectAndEdit(new)
    }

    func addPreviousSibling() {
        guard let sel = selectedElement, let parent = sel.topic.parent else { addChild(); return }
        let target = sel.topic
        let new = undoableAddChild(to: parent, text: "Topic")
        if let idx = parent.children.firstIndex(where: { $0 === target }) {
            parent.move(child: new, to: idx)
            rebuildElementsPublic()
        }
        inheritRootSide(from: target, to: new)
        selectAndEdit(new)
    }

    /// When the parent is the root, write an explicit `leftSide` attribute
    /// on `dst` matching `src`'s currently-displayed side. Without this the
    /// new sibling's index parity flips it to the opposite side at the next
    /// `balanceRoot` pass (bug #39 / #40).
    private func inheritRootSide(from src: Topic, to dst: Topic) {
        guard let parent = src.parent, parent === mindMap?.root else { return }
        let srcIsLeft = element(forTopic: src)?.isLeftSide ?? false
        dst.setAttribute(TopicAttribute.leftSide, srcIsLeft ? "true" : "false")
    }

    /// Resolve `topic` to an element, select it, and open the inline editor.
    /// No-op when the element hasn't been laid out yet (shouldn't happen for
    /// freshly-added topics since callers re-layout first).
    private func selectAndEdit(_ topic: Topic) {
        guard let el = element(forTopic: topic) else { return }
        selectElement(el)
        beginInlineEdit(on: el)
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
        // Tear down a previously-installed editor first. Without this,
        // repeated Tab keystrokes (each one starts a new child + a new
        // inline edit) accumulated NSTextField subviews on the canvas —
        // the user saw them as a horizontal pile of "topic" boxes that
        // looked like overlapping topics (bug #55).
        commitInlineEdit()

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
        inlineEditTarget = element.topic
    }

    @objc func commitInlineEdit() {
        guard let editor = inlineEditor else { return }
        let newText = editor.stringValue
        let target = inlineEditTarget
        editor.removeFromSuperview()
        inlineEditor = nil
        inlineEditTarget = nil
        if let target = target {
            undoableSetText(target, to: newText)
        }
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
