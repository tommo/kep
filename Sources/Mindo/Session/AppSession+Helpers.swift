import AppKit
import Foundation
import MindoBase
import MindoCore
import MindoMarkdown
import MindoMindMap
import MindoModel

/// Weak box so the session can hold region container views without keeping
/// them (or the window) alive.
final class WeakViewBox {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
}

extension AppSession {

    // MARK: - Active document

    /// Lookup helper — the document identified by `activeDocumentID`, if any.
    var activeDocument: OpenDocument? {
        guard let id = activeDocumentID else { return nil }
        return openDocuments.first { $0.id == id }
    }

    /// Properties of the topic currently selected in the mind-map canvas (via
    /// `selectedOutlineTarget`), for the inspector's property panel. nil when
    /// the active doc isn't a mind map or nothing is selected.
    /// The selected mind-map node's long-form markdown content (its Note
    /// extra). nil when nothing's selected, the note is empty, or it's
    /// encrypted (we don't preview ciphertext). Authored via the node's
    /// right-click → Note; rendered in the inspector's content pane.
    var selectedNodeContent: String? {
        guard case .mindMap(let map)? = activeDocument?.kind,
              let path = selectedOutlineTarget,
              let topic = map.topic(atOutlinePath: path),
              let note = topic.extra(.note) as? ExtraNote,
              !NoteEncryption.looksEncrypted(note.text),
              !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return note.text
    }

    /// The MindMapView backing the active mindmap document (found by walking
    /// the key window's tree, like the zoom commands do).
    @MainActor var activeMindMapView: MindMapView? {
        let win = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
        return win?.contentView?
            .firstSubview(ofType: NSScrollView.self, where: { $0.documentView is MindMapView })?
            .documentView as? MindMapView
    }

    /// Move keyboard focus to the active document's editor (mind-map canvas or
    /// text view). Used by the sidebar's Return key — the file is already open
    /// (browsing), Return commits focus to it.
    @MainActor func focusActiveEditor() {
        activeRegion = .document
        guard let win = NSApp.keyWindow ?? NSApp.mainWindow, let content = win.contentView else { return }
        if let mv = content.firstSubview(ofType: NSScrollView.self, where: { $0.documentView is MindMapView })?
            .documentView as? MindMapView {
            win.makeFirstResponder(mv)
            return
        }
        if let tv = content.firstSubview(ofType: NSScrollView.self, where: { $0.documentView is NSTextView })?
            .documentView as? NSTextView {
            win.makeFirstResponder(tv)
        }
    }

    /// The window's main regions, for keyboard focus switching (⌘1/2/3, ⌘\).
    enum FocusRegion { case sidebar, document, inspector, agent }

    /// Move keyboard focus to a region (revealing it first if collapsed). The
    /// keyboard-only navigation backbone — see [[feedback_keyboard_only_ux]].
    @MainActor func focusRegion(_ region: FocusRegion) {
        activeRegion = region
        switch region {
        case .sidebar:
            sidebarVisible = true
            focusAfterReveal { win, content in
                if let outline = content.firstSubview(ofType: NSOutlineView.self, where: { _ in true }) {
                    win.makeFirstResponder(outline)
                }
            }
        case .document:
            // A notebook's "document focus" is its SwiftUI command mode, which an
            // AppKit first-responder search can't reach — signal it directly.
            if activeFileType == .mindNotebook {
                NotificationCenter.default.post(name: .focusNotebookCommand, object: nil)
            } else {
                focusAfterReveal { _, _ in self.focusActiveEditor() }
            }
        case .inspector:
            outlineOpen = true
            inspectorTab = .inspector
            // Inspector content (Outline list) takes ↑↓ once shown.
        case .agent:
            outlineOpen = true
            inspectorTab = .agent   // DialogView auto-focuses its input on appear
        }
    }

    // MARK: - Focus tracking (highlight follows the real first responder)

    /// Record a region's container view, tagged by `RegionContainerTagger` in
    /// ContentView. We classify the first responder by testing which container
    /// it descends from, so the highlight follows clicks/Tab — not just ⌘1/2/3.
    @MainActor func registerRegionContainer(_ view: NSView, as region: FocusRegion) {
        regionContainers[region] = WeakViewBox(view)
    }

    /// Install (once) a local event monitor so any mouse click or Tab that
    /// moves the first responder re-syncs `activeRegion` to the pane that now
    /// holds focus. The monitor never consumes the event — it just observes.
    @MainActor func startRegionFocusTracking() {
        guard regionFocusMonitor == nil else { return }
        regionFocusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            // Only Tab (48) among key events relocates focus across panes;
            // ignore every other keystroke so typing stays cheap.
            if event.type == .keyDown && event.keyCode != 48 { return event }
            let isClick = event.type == .leftMouseDown
            let point = event.locationInWindow
            let window = event.window
            DispatchQueue.main.async {
                guard let self else { return }
                if isClick {
                    // A click maps to whichever pane it landed in — so clicking
                    // ANYWHERE (even a non-focusable spot outside the canvas)
                    // moves the focus ring, not only clicks that change the first
                    // responder.
                    self.applyRegionAtClick(point, in: window)
                } else {
                    // Tab: first responder updates after dispatch, read next turn.
                    self.syncActiveRegionToFirstResponder()
                }
            }
            return event
        }
    }

    /// Set `activeRegion` from a click's window-space location: the pane whose
    /// container frame contains the point. Pane frames don't overlap, so order
    /// doesn't matter.
    @MainActor private func applyRegionAtClick(_ point: NSPoint, in window: NSWindow?) {
        guard let win = window ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        for region in [FocusRegion.sidebar, .document, .inspector] {
            guard let c = regionContainers[region]?.view, c.window === win else { continue }
            if c.convert(c.bounds, to: nil).contains(point) { apply(region); return }
        }
    }

    /// Map the window's current first responder to its region and update the
    /// highlight. No-op when focus lands somewhere untagged (e.g. a toolbar) so
    /// the indicator never flickers off mid-edit.
    @MainActor func syncActiveRegionToFirstResponder() {
        guard let win = NSApp.keyWindow ?? NSApp.mainWindow,
              let responder = win.firstResponder as? NSView else { return }
        let order: [FocusRegion] = [.document, .sidebar, .inspector]

        // Primary: the responder lives inside a region's container subtree.
        for region in order where containsResponder(region, responder, geometric: false) {
            apply(region); return
        }
        // Fallback (robust to SwiftUI's view nesting): the responder's centre
        // falls within a region container's on-screen frame.
        for region in order where containsResponder(region, responder, geometric: true) {
            apply(region); return
        }
        // Untagged focus (toolbar, etc.) — leave the highlight where it is.
    }

    @MainActor private func containsResponder(_ region: FocusRegion, _ responder: NSView, geometric: Bool) -> Bool {
        guard let container = regionContainers[region]?.view else { return false }
        if !geometric { return responder == container || responder.isDescendant(of: container) }
        // A scrollable document view (the mind-map canvas) is far larger than its
        // viewport and its bounds-centre PANS off-screen — using it made the focus
        // ring jump between columns as you scrolled. Use the responder's enclosing
        // scroll view (a fixed, column-sized frame) so the mapping is stable.
        let target = responder.enclosingScrollView ?? responder
        let r = target.convert(target.bounds, to: nil)
        let c = container.convert(container.bounds, to: nil)
        return c.contains(NSPoint(x: r.midX, y: r.midY))
    }

    @MainActor private func apply(_ region: FocusRegion) {
        // The inspector pane hosts both the passive panels and the agent chat;
        // reflect whichever tab is showing.
        let resolved: FocusRegion = (region == .inspector && inspectorTab == .agent) ? .agent : region
        if activeRegion != resolved { activeRegion = resolved }
    }

    /// Run `body` on the next runloop turns so a just-revealed column/panel has
    /// been laid out before we hunt for its view to focus.
    @MainActor private func focusAfterReveal(_ body: @escaping (NSWindow, NSView) -> Void) {
        DispatchQueue.main.async {
            guard let win = NSApp.keyWindow ?? NSApp.mainWindow, let content = win.contentView else { return }
            body(win, content)
        }
    }

    /// Write the selected node's markdown content (its Note). Empty clears it.
    /// The note BADGE only changes when content appears/disappears, so we only
    /// rebuild the canvas then — typing into existing content just updates the
    /// model + marks the doc dirty (no per-keystroke canvas churn).
    @MainActor func setSelectedNodeContent(_ text: String) {
        guard case .mindMap(let map)? = activeDocument?.kind,
              let path = selectedOutlineTarget,
              let topic = map.topic(atOutlinePath: path) else { return }
        let had = topic.extra(.note) != nil
        if text.isEmpty {
            topic.removeExtra(.note)
        } else {
            topic.setExtra(ExtraNote(text: text))
        }
        if let id = activeDocumentID, let idx = openDocuments.firstIndex(where: { $0.id == id }),
           !openDocuments[idx].isDirty {
            openDocuments[idx].isDirty = true   // only when it flips, to avoid extra re-renders
        }
        if had != !text.isEmpty { activeMindMapView?.rebuildElementsPublic() }
    }

    var selectedNodeProperties: NodeProperties? {
        guard case .mindMap(let map)? = activeDocument?.kind,
              let path = selectedOutlineTarget,
              let topic = map.topic(atOutlinePath: path) else { return nil }
        return NodeProperties.from(topic: topic, path: path, map: map)
    }

    // MARK: - Typed node properties (keystone #200 — inspector consumer)

    /// The topic currently selected on the canvas, or nil. Pure model lookup.
    var selectedTopic: Topic? {
        guard case .mindMap(let map)? = activeDocument?.kind,
              let path = selectedOutlineTarget else { return nil }
        return map.topic(atOutlinePath: path)
    }

    /// User (typed) properties of the selected node, as an Equatable snapshot so
    /// the inspector form refreshes on selection change (Topic is a reference
    /// type SwiftUI can't observe directly).
    var selectedNodeUserProperties: [NodePropertyRow] {
        guard let topic = selectedTopic else { return [] }
        return topic.propertyKeys.map {
            NodePropertyRow(key: $0, value: topic.property($0) ?? .text(topic.attribute($0) ?? ""))
        }
    }

    /// Distinct tags in the active mind map, with per-tag topic counts.
    var activeMindMapTagCounts: [(tag: String, count: Int)] {
        guard case .mindMap(let map)? = activeDocument?.kind else { return [] }
        return MindMapTags.tagCounts(in: map)
    }

    /// Select every topic in the active map carrying `tag` (the inspector tag
    /// filter). Reuses the canvas multi-selection.
    @MainActor func selectTopicsWithTag(_ tag: String) {
        guard case .mindMap(let map)? = activeDocument?.kind else { return }
        activeMindMapView?.selectTopics(MindMapTags.topicsWithTag(tag, in: map))
    }

    /// Matching topics for `query` as (outline-path, text, markers) rows — the
    /// results "view" for the inspector. Markers (priority/done/progress/tags)
    /// give it the at-a-glance Bases feel. Empty for a blank query / non-mindmap.
    func queryResults(_ query: String) -> [(path: String, text: String, markers: [PropertyMarker])] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, case .mindMap(let map)? = activeDocument?.kind else { return [] }
        return TopicQuery.evaluate(q, in: map).map {
            (path: $0.outlinePath,
             text: $0.text.isEmpty ? "·" : $0.text,
             markers: PropertyMarkers.markerRow(for: $0))
        }
    }

    /// Select every topic in the active map matching the query (TopicQuery
    /// mini-language: `key:value`, `#tag`, bare text; space = AND). Returns the
    /// match count so the UI can report it; no-op for a blank query.
    @MainActor @discardableResult func selectTopicsMatching(_ query: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, case .mindMap(let map)? = activeDocument?.kind else { return 0 }
        let topics = TopicQuery.evaluate(q, in: map)
        activeMindMapView?.selectTopics(topics)
        return topics.count
    }

    /// Well-known keys that render a canvas marker — editing one must relayout
    /// the canvas so the marker strip appears/updates.
    private var markerKeys: Set<String> {
        [PropertyMarkers.priorityKey, PropertyMarkers.doneKey,
         PropertyMarkers.progressKey, PropertyMarkers.tagsKey]
    }

    /// Set or clear (nil) a typed property on the selected node.
    @MainActor func setSelectedNodeProperty(_ key: String, _ value: PropertyValue?) {
        guard let topic = selectedTopic else { return }
        topic.setProperty(key, value)
        markActiveDocumentDirty()
        if markerKeys.contains(key) { activeMindMapView?.rebuildElementsPublic() }
    }

    /// Add a property whose type is inferred from the raw string. No-op for an
    /// empty, reserved, or already-present key.
    @MainActor func addSelectedNodeProperty(key rawKey: String, rawValue: String) {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !Topic.isReservedAttributeKey(key),
              let topic = selectedTopic, topic.attribute(key) == nil else { return }
        topic.setProperty(key, PropertyInference.infer(rawValue))
        markActiveDocumentDirty()
        if markerKeys.contains(key) { activeMindMapView?.rebuildElementsPublic() }
    }

    /// Rename the topic at `path` (an outline index path) to `newText` through
    /// the canvas undo path, so an inline outline edit relayouts, redraws, marks
    /// the doc dirty and is undoable — the first two-way slice of T2 (#201).
    @MainActor func renameOutlineTopic(atOutlinePath path: String, to newText: String) {
        guard case .mindMap(let map)? = activeDocument?.kind,
              let topic = map.topic(atOutlinePath: path),
              let view = activeMindMapView else { return }
        view.undoableSetText(topic, to: newText)
    }

    /// Reorder/reparent the topic at `path` from the outline (T2 #201). All four
    /// moves go through `undoableReparent` (one undo step) and re-select the moved
    /// topic so the canvas + outline highlight follow it.
    @MainActor func moveOutlineTopic(atOutlinePath path: String, _ move: OutlineMove) {
        guard case .mindMap(let map)? = activeDocument?.kind,
              let topic = map.topic(atOutlinePath: path),
              let view = activeMindMapView else { return }
        let modelMove: TopicMove
        switch move {
        case .up:      modelMove = .up
        case .down:    modelMove = .down
        case .indent:  modelMove = .indent
        case .outdent: modelMove = .outdent
        }
        guard let plan = topic.movePlan(modelMove) else { return }
        view.undoableReparent(topic, to: plan.newParent, at: plan.index)
        view.selectTopics([topic])
    }

    /// Toggle the fold state of the topic at `path` from the outline, through the
    /// canvas undoable setter so the map relayouts and the outline (which omits a
    /// collapsed node's descendants) mirrors it. No-op for a childless node.
    @MainActor func toggleOutlineCollapse(atOutlinePath path: String) {
        guard case .mindMap(let map)? = activeDocument?.kind,
              let topic = map.topic(atOutlinePath: path), !topic.children.isEmpty,
              let view = activeMindMapView else { return }
        let collapsed = topic.attribute(TopicAttribute.collapsed) == "true"
        view.undoableSetAttribute(topic, key: TopicAttribute.collapsed, value: collapsed ? nil : "true")
    }

    /// Apply a built-in supertag template (keystone #200) to the selected node,
    /// stamping any missing typed properties with their defaults. Returns the
    /// keys that were added (empty if none/no selection/unknown template).
    @MainActor @discardableResult func applySupertag(named name: String) -> [String] {
        guard let topic = selectedTopic, let tag = SupertagCatalog.named(name) else { return [] }
        let added = tag.apply(to: topic)
        guard !added.isEmpty else { return [] }
        markActiveDocumentDirty()
        if added.contains(where: { markerKeys.contains($0) }) {
            activeMindMapView?.rebuildElementsPublic()
        }
        return added
    }

    @MainActor func removeSelectedNodeProperty(_ key: String) {
        guard let topic = selectedTopic else { return }
        topic.setProperty(key, nil)
        markActiveDocumentDirty()
        if markerKeys.contains(key) { activeMindMapView?.rebuildElementsPublic() }
    }

    /// Flip the active doc to dirty (once) so a property edit is saved.
    private func markActiveDocumentDirty() {
        if let id = activeDocumentID, let idx = openDocuments.firstIndex(where: { $0.id == id }),
           !openDocuments[idx].isDirty {
            openDocuments[idx].isDirty = true
        }
    }

    // MARK: - Per-document mind-map theme

    /// Map attribute key for a per-document theme override. Stored in the `.mmd`
    /// map-level attributes so it travels with the file.
    static let mapThemeAttr = "theme"

    /// The active mind map's own theme override, or nil to use the global theme.
    var activeMapThemeChoice: ThemeChoice? {
        guard case .mindMap(let map)? = activeDocument?.kind,
              let raw = map.attributes[Self.mapThemeAttr] else { return nil }
        return ThemeChoice(rawValue: raw)
    }

    /// Set (or clear, with nil) the active mind map's theme override. Persists in
    /// the map attributes and re-resolves the live canvas theme.
    @MainActor func setActiveMapThemeChoice(_ choice: ThemeChoice?) {
        guard case .mindMap(let map)? = activeDocument?.kind else { return }
        map.setAttribute(Self.mapThemeAttr, choice?.rawValue)
        markActiveDocumentDirty()
        canvasThemeRevision &+= 1   // DetailArea reads this → re-resolves the theme
    }

    /// The active mind map's connector (curve) style override, or nil for global.
    var activeMapConnectorStyle: ConnectorStyle? {
        guard case .mindMap(let map)? = activeDocument?.kind,
              let raw = map.attributes[MindMapView.connectorStyleAttr] else { return nil }
        return ConnectorStyle(rawValue: raw)
    }

    /// Set (or clear, with nil) the active mind map's connector style and redraw.
    @MainActor func setActiveMapConnectorStyle(_ style: ConnectorStyle?) {
        guard case .mindMap(let map)? = activeDocument?.kind else { return }
        map.setAttribute(MindMapView.connectorStyleAttr, style?.rawValue)
        markActiveDocumentDirty()
        activeMindMapView?.needsDisplay = true   // connector style is read at draw time
    }

    // MARK: - Outline navigation

    /// Push a navigation target into the active editor. Tags the value with a
    /// trailing UUID so two clicks on the same outline row re-fire — the
    /// editor coordinator only acts on string change.
    func requestOutlineNavigation(target: String) {
        outlineNavigationTarget = "\(target)#\(UUID().uuidString)"
    }

    /// Strip the disambiguation suffix the active editor was passed.
    var sanitizedNavigationTarget: String? {
        guard let target = outlineNavigationTarget else { return nil }
        return target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }

    // MARK: - Active doc accessors

    /// True when the active document is a markdown text doc (powers Export menu enabling).
    var activeIsMarkdown: Bool { activeFileType == .markdown }

    /// True when at least one open document is dirty AND has a file URL
    /// (so Save All has something it can actually flush; untitled docs
    /// are skipped by saveAllDirty for UX reasons — see that method).
    var hasDirtyOpenDocuments: Bool {
        openDocuments.contains { $0.isDirty && $0.fileURL != nil }
    }

    var activeFileType: SupportedFileType? {
        guard let doc = activeDocument else { return nil }
        switch doc.kind {
        case .mindMap: return .mindMap
        case .text(_, let t): return t
        case .unsupported: return nil
        }
    }

    /// Route ⌘F to the appropriate Find affordance for the active doc:
    /// mindmap → toggles the in-document find bar overlay; text editors
    /// (markdown / plantuml / csv) → invokes NSTextView's built-in find
    /// bar via the standard NSTextFinderClient action.
    @MainActor
    func invokeFindInActiveDocument() {
        guard let doc = activeDocument else { return }
        switch doc.kind {
        case .mindMap:
            inDocFindOpen.toggle()
        case .text(_, .csv):
            // CSV uses an NSTableView, not an NSTextView, so the standard
            // find bar can't drive it — toggle our native CSV find/replace
            // bar (the editor observes this flag via a binding).
            csvFindOpen.toggle()
        case .text, .unsupported:
            // Route performFindPanelAction: through the responder chain so
            // NSTextView's built-in find bar (usesFindBar=true) takes over.
            // The sender MUST carry tag = showFindPanel — performFindPanelAction
            // reads sender.tag to pick the operation, and the old nil sender's
            // tag-0 was an invalid action, so ⌘F silently did nothing.
            TextFindBar.showFindBar()
        }
    }

    // MARK: - Snippets

    func insertSnippet(_ snippet: Snippet) {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        let expanded = SnippetExpander.expand(snippet.body, context: snippetContext(for: openDocuments[idx]))
        switch openDocuments[idx].kind {
        case .text(let body, let t):
            let glue = body.hasSuffix("\n") || body.isEmpty ? "" : "\n"
            openDocuments[idx].kind = .text(body + glue + expanded, fileType: t)
        case .mindMap(let map):
            appendLinesAsChildren(of: map, text: expanded)
        case .unsupported:
            break
        }
    }

    /// Build the per-doc context that `${filename}` and `${title}` need.
    private func snippetContext(for doc: OpenDocument) -> SnippetExpander.Context {
        let filename = doc.fileURL?.deletingPathExtension().lastPathComponent ?? ""
        var title = ""
        if case .mindMap(let map) = doc.kind { title = map.root?.text ?? "" }
        return SnippetExpander.Context(filename: filename, title: title)
    }

    /// Split `text` by line and add each non-empty line as a child of the
    /// map's root, creating the root if missing. Shared by snippet insertion
    /// and AI childTopic generation.
    func appendLinesAsChildren(of map: MindMap, text: String) {
        let parent = map.root ?? Topic(text: "Root")
        if map.root == nil { map.root = parent }
        for line in text.split(whereSeparator: { $0 == "\n" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            _ = parent.addChild(text: trimmed)
        }
    }
}
