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

    /// Optional injected undo manager. When set, takes precedence over the
    /// responder-chain default (`super.undoManager`). Useful for tests and for
    /// callers that want a per-document undo stack.
    public var injectedUndoManager: UndoManager?

    public override var undoManager: UndoManager? {
        injectedUndoManager ?? super.undoManager
    }

    /// Called whenever the mind map mutates. UI layer can persist or mark dirty.
    public var onChange: ((MindMap) -> Void)?

    private var layoutEngine: MindMapLayout
    private var contentBounds: CGRect = .zero
    private var inlineEditor: NSTextField?

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
        needsDisplay = true
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

        let minWidth = max(self.bounds.width, contentBounds.width + 64)
        let minHeight = max(self.bounds.height, contentBounds.height + 64)
        if let parent = enclosingScrollView {
            self.frame = CGRect(x: 0, y: 0, width: minWidth, height: minHeight)
            parent.documentView?.frame.size = CGSize(width: minWidth, height: minHeight)
        } else {
            self.frame.size = CGSize(width: minWidth, height: minHeight)
        }
        needsDisplay = true
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

        // Selection overlay on top.
        if let sel = selectedElement {
            ctx.setStrokeColor(theme.selectionColor.cgColor)
            ctx.setLineWidth(theme.selectionWidth)
            let rect = sel.frame.insetBy(dx: -3, dy: -3)
            let path = CGPath(roundedRect: rect, cornerWidth: theme.cornerRadius + 3, cornerHeight: theme.cornerRadius + 3, transform: nil)
            ctx.addPath(path)
            ctx.strokePath()
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

        // Text.
        let font = theme.font(forLevel: level)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.textColor(forLevel: level),
            .paragraphStyle: style,
        ]
        let textRect = el.frame.insetBy(dx: theme.textInsets.left, dy: theme.textInsets.top)
        let displayText = el.topic.text.isEmpty ? "·" : el.topic.text
        (displayText as NSString).draw(in: textRect, withAttributes: attrs)

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

    public override func mouseDown(with event: NSEvent) {
        commitInlineEdit()
        let p = convert(event.locationInWindow, from: nil)
        let el = element(at: p)
        select(el)
        if event.clickCount == 2, let el = el {
            beginInlineEdit(on: el)
        }
        window?.makeFirstResponder(self)
    }

    // MARK: - Keyboard

    public override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else { super.keyDown(with: event); return }
        let isShift = event.modifierFlags.contains(.shift)

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
            move(.left)
        case String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)):
            move(.right)
        case String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)):
            move(.up)
        case String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)):
            move(.down)
        default:
            super.keyDown(with: event)
        }
    }

    private enum Direction { case left, right, up, down }

    private func move(_ direction: Direction) {
        guard let sel = selectedElement, let root = rootElement else { return }
        switch direction {
        case .right:
            if let target = sel.children.first(where: { !$0.isLeftSide }) ?? sel.children.first { select(target) }
            else if sel === root { select(root.rightChildren.first) }
        case .left:
            if let target = sel.children.first(where: { $0.isLeftSide }) { select(target) }
            else if sel === root { select(root.leftChildren.first) }
            else if let parent = sel.topic.parent, let parentEl = element(for: parent) { select(parentEl) }
        case .up, .down:
            guard let parent = sel.topic.parent, let parentEl = element(for: parent) else { return }
            let siblings = parentEl.children.filter { $0.isLeftSide == sel.isLeftSide }
            if let idx = siblings.firstIndex(where: { $0 === sel }) {
                let next = direction == .up ? idx - 1 : idx + 1
                if siblings.indices.contains(next) { select(siblings[next]) }
            }
        }
    }

    private func element(for topic: Topic) -> MindMapElement? {
        var found: MindMapElement?
        rootElement?.traverse { if $0.topic === topic { found = $0 } }
        return found
    }

    // MARK: - Edits

    private func select(_ element: MindMapElement?) {
        selectedElement = element
        needsDisplay = true
        if let el = element { scrollToVisible(el.frame.insetBy(dx: -32, dy: -32)) }
    }

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
        guard let sel = selectedElement, sel.topic.parent != nil else { return }
        let parent = sel.topic.parent
        undoableRemove(sel.topic)
        if let p = parent { select(element(for: p)) }
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
