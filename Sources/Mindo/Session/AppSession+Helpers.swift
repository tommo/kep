import AppKit
import Foundation
import MindoBase
import MindoCore
import MindoMindMap
import MindoModel

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
        switch region {
        case .sidebar:
            sidebarVisible = true
            focusAfterReveal { win, content in
                if let outline = content.firstSubview(ofType: NSOutlineView.self, where: { _ in true }) {
                    win.makeFirstResponder(outline)
                }
            }
        case .document:
            focusAfterReveal { _, _ in self.focusActiveEditor() }
        case .inspector:
            outlineOpen = true
            inspectorTab = .inspector
            // Inspector content (Outline list) takes ↑↓ once shown.
        case .agent:
            outlineOpen = true
            inspectorTab = .agent   // DialogView auto-focuses its input on appear
        }
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
