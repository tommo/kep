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

    /// Build an NSMenu of Add/Edit/Remove actions for Note, Link, File extras
    /// plus an Image submenu for the `mmd.image` attribute.
    private func makeContextMenu(for element: MindMapElement) -> NSMenu {
        let menu = NSMenu()
        addExtraSection(menu, type: .note, target: element, label: "Note", placeholder: "Note text")
        addExtraSection(menu, type: .link, target: element, label: "Link", placeholder: "https://example.com")
        addExtraSection(menu, type: .file, target: element, label: "File", placeholder: "/path/to/file")
        menu.addItem(NSMenuItem.separator())
        let hasImage = element.topic.attribute(TopicAttribute.image) != nil
        let imageItem = NSMenuItem(
            title: hasImage ? "Replace Image…" : "Add Image…",
            action: #selector(contextSetImage(_:)),
            keyEquivalent: ""
        )
        imageItem.target = self
        imageItem.representedObject = element
        menu.addItem(imageItem)
        if hasImage {
            let removeImage = NSMenuItem(title: "Remove Image", action: #selector(contextRemoveImage(_:)), keyEquivalent: "")
            removeImage.target = self
            removeImage.representedObject = element
            menu.addItem(removeImage)
        }
        menu.addItem(NSMenuItem.separator())
        let deleteItem = NSMenuItem(title: "Delete Topic", action: #selector(contextDeleteTopic(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = element
        deleteItem.isEnabled = element.topic.parent != nil
        menu.addItem(deleteItem)
        return menu
    }

    @objc private func contextSetImage(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        let base64 = data.base64EncodedString()
        undoableSetAttribute(element.topic, key: TopicAttribute.image, value: base64)
    }

    @objc private func contextRemoveImage(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        undoableSetAttribute(element.topic, key: TopicAttribute.image, value: nil)
    }

    private func addExtraSection(_ menu: NSMenu, type: ExtraType, target element: MindMapElement, label: String, placeholder: String) {
        let exists = element.topic.extra(type) != nil
        if exists {
            let editItem = NSMenuItem(title: "Edit \(label)…", action: #selector(contextEditExtra(_:)), keyEquivalent: "")
            editItem.target = self
            editItem.representedObject = ExtraMenuPayload(element: element, type: type, placeholder: placeholder)
            menu.addItem(editItem)

            let removeItem = NSMenuItem(title: "Remove \(label)", action: #selector(contextRemoveExtra(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = ExtraMenuPayload(element: element, type: type, placeholder: placeholder)
            menu.addItem(removeItem)
        } else {
            let addItem = NSMenuItem(title: "Add \(label)…", action: #selector(contextEditExtra(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = ExtraMenuPayload(element: element, type: type, placeholder: placeholder)
            menu.addItem(addItem)
        }
    }

    @objc private func contextEditExtra(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ExtraMenuPayload else { return }
        let current = payload.element.topic.extra(payload.type)?.value ?? ""
        guard let value = promptForExtraValue(
            title: "\(payload.type == .note ? "Note" : payload.type == .link ? "Link" : "File")",
            placeholder: payload.placeholder,
            initial: current
        ) else { return }
        let extra: any Extra
        switch payload.type {
        case .note: extra = ExtraNote(text: value)
        case .link: extra = ExtraLink(uri: value)
        case .file: extra = ExtraFile(uri: value)
        case .topic: extra = ExtraTopic(topicUID: value)
        case .unknown: return
        }
        undoableSetExtra(payload.element.topic, payload.type, value: extra)
    }

    @objc private func contextRemoveExtra(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ExtraMenuPayload else { return }
        undoableSetExtra(payload.element.topic, payload.type, value: nil)
    }

    @objc private func contextDeleteTopic(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        undoableRemove(element.topic)
        if let parent = element.topic.parent { select(self.element(for: parent)) }
    }

    /// Show a modal NSAlert with a text field. Returns nil when the user
    /// cancels. Returns the trimmed value otherwise (empty string is allowed
    /// for Note; the caller is responsible for type-specific validation).
    private func promptForExtraValue(title: String, placeholder: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter the value"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 80))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 80))
        textView.isRichText = false
        textView.string = initial
        textView.font = .systemFont(ofSize: 13)
        textView.isEditable = true
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        alert.accessoryView = scroll
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let result = alert.runModal()
        guard result == .alertFirstButtonReturn else { return nil }
        return textView.string
    }

    private struct ExtraMenuPayload {
        let element: MindMapElement
        let type: ExtraType
        let placeholder: String
    }

    public override func mouseDown(with event: NSEvent) {
        commitInlineEdit()
        let p = convert(event.locationInWindow, from: nil)
        // Extra-icon hit-test runs first so clicks on the icon strip don't
        // start a drag or change selection.
        if let (el, type) = elementExtra(at: p) {
            handleExtraTap(on: el, type: type)
            return
        }
        let el = element(at: p)
        select(el)
        if event.clickCount == 2, let el = el {
            beginInlineEdit(on: el)
        } else if let el = el, el.topic.parent != nil {
            // Arm a potential drag on any non-root topic. Root cannot move.
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
