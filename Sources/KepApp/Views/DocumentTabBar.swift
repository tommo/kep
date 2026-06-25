import AppKit
import SwiftUI
import UniformTypeIdentifiers
import KepCore

/// A single native AppKit tab-strip view. It owns mouse tracking and drag
/// reordering directly, so the hidden title bar cannot reinterpret tab drags
/// as window movement.
struct DocumentTabBar: NSViewRepresentable {
    @Binding var session: AppSession

    func makeNSView(context: Context) -> NativeDocumentTabStrip {
        NativeDocumentTabStrip()
    }

    func updateNSView(_ view: NativeDocumentTabStrip, context: Context) {
        view.configure(
            documents: session.openDocuments,
            activeID: session.activeDocumentID,
            select: { id in
                session.pendingEditorFocus = true
                session.activeDocumentID = id
                session.persistOpenTabs()
            },
            close: session.closeTab,
            closeOthers: { session.closeOtherTabs(keep: $0) },
            closeAll: session.closeAllTabs,
            reload: session.reloadTab,
            reveal: { id in
                guard let url = session.openDocuments.first(where: { $0.id == id })?.fileURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            reorder: { id, insertionIndex in
                let ids = session.openDocuments.map(\.id)
                let reorderedIDs = TabReorder.move(
                    ids,
                    from: id,
                    toInsertionIndex: insertionIndex
                )
                guard reorderedIDs != ids else { return }
                let byID = Dictionary(uniqueKeysWithValues: session.openDocuments.map { ($0.id, $0) })
                session.openDocuments = reorderedIDs.compactMap { byID[$0] }
                session.persistOpenTabs()
            },
            openFiles: { urls in
                for url in urls {
                    session.open(url: url, inNewTab: true)
                }
            },
            create: session.newDocViewTab
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NativeDocumentTabStrip,
        context: Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 52)
    }
}

final class NativeDocumentTabStrip: NSView {
    private static let tabHeight: CGFloat = 28
    private static let spacing: CGFloat = 4
    private static let horizontalInset: CGFloat = 8
    private static let newButtonWidth: CGFloat = 30

    private var documents: [OpenDocument] = []
    private var activeID: UUID?
    private var tabFrames: [(id: UUID, frame: NSRect)] = []
    private var closeFrames: [UUID: NSRect] = [:]
    private var newButtonFrame = NSRect.zero
    private var scrollOffset: CGFloat = 0

    private var selectAction: ((UUID) -> Void)?
    private var closeAction: ((UUID) -> Void)?
    private var closeOthersAction: ((UUID) -> Void)?
    private var closeAllAction: (() -> Void)?
    private var reloadAction: ((UUID) -> Void)?
    private var revealAction: ((UUID) -> Void)?
    private var reorderAction: ((UUID, Int) -> Void)?
    private var openFilesAction: (([URL]) -> Void)?
    private var createAction: ((SupportedFileType) -> Void)?

    private enum PressTarget {
        case tab(UUID)
        case close(UUID)
        case newDocument
    }

    private var pressTarget: PressTarget?
    private var mouseDownPoint = NSPoint.zero
    private var isReordering = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 52)
    }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        registerForDraggedTypes([.fileURL])
        setAccessibilityRole(.tabGroup)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        documents: [OpenDocument],
        activeID: UUID?,
        select: @escaping (UUID) -> Void,
        close: @escaping (UUID) -> Void,
        closeOthers: @escaping (UUID) -> Void,
        closeAll: @escaping () -> Void,
        reload: @escaping (UUID) -> Void,
        reveal: @escaping (UUID) -> Void,
        reorder: @escaping (UUID, Int) -> Void,
        openFiles: @escaping ([URL]) -> Void,
        create: @escaping (SupportedFileType) -> Void
    ) {
        self.documents = documents
        self.activeID = activeID
        selectAction = select
        closeAction = close
        closeOthersAction = closeOthers
        closeAllAction = closeAll
        reloadAction = reload
        revealAction = reveal
        reorderAction = reorder
        openFilesAction = openFiles
        createAction = create
        clampScrollOffset()
        scrollActiveTabIntoView()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        clampScrollOffset()
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        rebuildFrames()

        for (index, entry) in tabFrames.enumerated() where documents.indices.contains(index) {
            drawTab(documents[index], in: entry.frame)
        }
        drawNewButton()
    }

    private func rebuildFrames() {
        tabFrames.removeAll(keepingCapacity: true)
        closeFrames.removeAll(keepingCapacity: true)

        let y = max(0, (bounds.height - Self.tabHeight) / 2)
        var x = Self.horizontalInset - scrollOffset
        for document in documents {
            let width = tabWidth(for: document)
            let frame = NSRect(x: x, y: y, width: width, height: Self.tabHeight)
            tabFrames.append((document.id, frame))
            closeFrames[document.id] = NSRect(
                x: frame.maxX - 22,
                y: frame.minY + 6,
                width: 16,
                height: 16
            )
            x = frame.maxX + Self.spacing
        }
        newButtonFrame = NSRect(
            x: max(Self.horizontalInset, bounds.width - Self.newButtonWidth - 4),
            y: y,
            width: Self.newButtonWidth,
            height: Self.tabHeight
        )
    }

    private func drawTab(_ document: OpenDocument, in frame: NSRect) {
        guard frame.maxX >= 0, frame.minX <= newButtonFrame.minX else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(
            x: newButtonFrame.minX,
            y: 0,
            width: bounds.maxX - newButtonFrame.minX,
            height: bounds.height
        )).addClip()
        NSGraphicsContext.restoreGraphicsState()

        if document.id == activeID {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
        }

        let iconRect = NSRect(x: frame.minX + 8, y: frame.minY + 6.5, width: 15, height: 15)
        NSImage(
            systemSymbolName: tabIconName(for: document),
            accessibilityDescription: document.title
        )?.draw(in: iconRect)

        var titleMaxX = frame.maxX - 26
        if document.hasExternalChanges || document.isDirty {
            let dotRect = NSRect(x: titleMaxX - 10, y: frame.midY - 3, width: 6, height: 6)
            (document.hasExternalChanges ? NSColor.systemOrange : NSColor.secondaryLabelColor).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            titleMaxX -= 14
        }

        let titleRect = NSRect(
            x: iconRect.maxX + 6,
            y: frame.minY + 5,
            width: max(8, titleMaxX - iconRect.maxX - 8),
            height: 18
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (document.title as NSString).draw(
            in: titleRect,
            withAttributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        )

        if let closeRect = closeFrames[document.id] {
            NSImage(
                systemSymbolName: "xmark",
                accessibilityDescription: L("tab.menu.close")
            )?.draw(in: closeRect.insetBy(dx: 2, dy: 2))
        }
    }

    private func drawNewButton() {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(
            x: newButtonFrame.minX - 2,
            y: 0,
            width: bounds.maxX - newButtonFrame.minX + 2,
            height: bounds.height
        )).fill()
        NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: L("tab.new_document")
        )?.draw(in: newButtonFrame.insetBy(dx: 7, dy: 6))
    }

    // MARK: Mouse input and reorder

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = point
        isReordering = false
        if newButtonFrame.contains(point) {
            pressTarget = .newDocument
            return
        }
        if let close = closeFrames.first(where: { $0.value.contains(point) }) {
            pressTarget = .close(close.key)
            return
        }
        if let tab = tabFrames.first(where: { $0.frame.contains(point) }) {
            pressTarget = .tab(tab.id)
        } else {
            pressTarget = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard case .tab(let id) = pressTarget else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !isReordering {
            guard hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) >= 4 else { return }
            isReordering = true
        }
        let insertionIndex = insertionIndex(at: point.x)
        let oldIDs = documents.map(\.id)
        let newIDs = TabReorder.move(oldIDs, from: id, toInsertionIndex: insertionIndex)
        guard newIDs != oldIDs else { return }
        let byID = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        documents = newIDs.compactMap { byID[$0] }
        reorderAction?(id, insertionIndex)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressTarget = nil
            isReordering = false
        }
        guard !isReordering else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch pressTarget {
        case .tab(let id):
            if tabFrames.first(where: { $0.id == id })?.frame.contains(point) == true {
                selectAction?(id)
            }
        case .close(let id):
            if closeFrames[id]?.contains(point) == true {
                closeAction?(id)
            }
        case .newDocument:
            if newButtonFrame.contains(point) {
                showNewDocumentMenu()
            }
        case nil:
            break
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let id = tabFrames.first(where: { $0.frame.contains(point) })?.id else { return }
        contextMenu(for: id).popUp(positioning: nil, at: point, in: self)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        scrollOffset -= delta
        clampScrollOffset()
        needsDisplay = true
    }

    // MARK: Menus

    private func contextMenu(for id: UUID) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(actionItem(L("tab.menu.close"), #selector(closeMenuItem(_:)), id))
        let closeOthers = actionItem(L("tab.menu.close_others"), #selector(closeOthersMenuItem(_:)), id)
        closeOthers.isEnabled = documents.count > 1
        menu.addItem(closeOthers)
        menu.addItem(actionItem(L("tab.menu.close_all"), #selector(closeAllMenuItem(_:)), id))
        menu.addItem(.separator())

        let document = documents.first(where: { $0.id == id })
        let reload = actionItem(L("tab.menu.reload"), #selector(reloadMenuItem(_:)), id)
        reload.isEnabled = document?.hasExternalChanges == true
        menu.addItem(reload)
        let reveal = actionItem(L("tab.menu.reveal_in_finder"), #selector(revealMenuItem(_:)), id)
        reveal.isEnabled = document?.fileURL != nil
        menu.addItem(reveal)
        return menu
    }

    private func actionItem(_ title: String, _ action: Selector, _ id: UUID) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        return item
    }

    private func menuID(_ sender: Any?) -> UUID? {
        (sender as? NSMenuItem)?.representedObject as? UUID
    }

    @objc private func closeMenuItem(_ sender: Any?) {
        if let id = menuID(sender) { closeAction?(id) }
    }

    @objc private func closeOthersMenuItem(_ sender: Any?) {
        if let id = menuID(sender) { closeOthersAction?(id) }
    }

    @objc private func closeAllMenuItem(_ sender: Any?) {
        closeAllAction?()
    }

    @objc private func reloadMenuItem(_ sender: Any?) {
        if let id = menuID(sender) { reloadAction?(id) }
    }

    @objc private func revealMenuItem(_ sender: Any?) {
        if let id = menuID(sender) { revealAction?(id) }
    }

    private func showNewDocumentMenu() {
        let menu = NSMenu()
        addNewDocumentItem(L("menu.file.new_mindmap"), .mindMap, to: menu)
        addNewDocumentItem(L("menu.file.new_markdown"), .markdown, to: menu)
        addNewDocumentItem(L("menu.file.new_csv"), .csv, to: menu)
        addNewDocumentItem(L("menu.file.new_plantuml"), .plantUML, to: menu)
        addNewDocumentItem(L("menu.file.new_notebook"), .mindNotebook, to: menu)
        addNewDocumentItem(L("menu.file.new_text"), .plainText, to: menu)
        menu.popUp(positioning: nil, at: NSPoint(x: newButtonFrame.minX, y: newButtonFrame.maxY), in: self)
    }

    private func addNewDocumentItem(_ title: String, _ type: SupportedFileType, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(newDocumentMenuItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = type.rawValue
        menu.addItem(item)
    }

    @objc private func newDocumentMenuItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let type = SupportedFileType(rawValue: rawValue) else { return }
        createAction?(type)
    }

    // MARK: Finder file drops

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL], !urls.isEmpty else {
            return false
        }
        openFilesAction?(urls)
        return true
    }

    // MARK: Geometry

    private func tabWidth(for document: OpenDocument) -> CGFloat {
        let titleWidth = (document.title as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        ).width
        let statusWidth: CGFloat = (document.hasExternalChanges || document.isDirty) ? 12 : 0
        return min(260, max(110, ceil(titleWidth) + 16 + 18 + statusWidth + 34))
    }

    private var contentWidth: CGFloat {
        documents.reduce(Self.horizontalInset) {
            $0 + tabWidth(for: $1) + Self.spacing
        }
    }

    private var visibleTabWidth: CGFloat {
        max(1, bounds.width - Self.newButtonWidth - 8)
    }

    private func clampScrollOffset() {
        scrollOffset = min(max(0, scrollOffset), max(0, contentWidth - visibleTabWidth))
    }

    private func scrollActiveTabIntoView() {
        guard let activeID,
              let index = documents.firstIndex(where: { $0.id == activeID }) else { return }
        var minX = Self.horizontalInset
        for document in documents.prefix(index) {
            minX += tabWidth(for: document) + Self.spacing
        }
        let maxX = minX + tabWidth(for: documents[index])
        if minX < scrollOffset {
            scrollOffset = minX
        } else if maxX > scrollOffset + visibleTabWidth {
            scrollOffset = maxX - visibleTabWidth
        }
        clampScrollOffset()
    }

    private func insertionIndex(at viewX: CGFloat) -> Int {
        let contentX = viewX + scrollOffset
        var x = Self.horizontalInset
        for (index, document) in documents.enumerated() {
            let width = tabWidth(for: document)
            if contentX < x + width / 2 { return index }
            x += width + Self.spacing
        }
        return documents.count
    }
}

private func tabIconName(for document: OpenDocument) -> String {
    switch document.kind {
    case .mindMap:
        return SupportedFileType.mindMap.sfSymbolName
    case .text(_, let type):
        return (type ?? .plainText).sfSymbolName
    case .unsupported:
        return SupportedFileType.unknownSymbolName
    }
}
