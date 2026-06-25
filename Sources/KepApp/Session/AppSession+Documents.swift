import AppKit
import UniformTypeIdentifiers
import KepCore
import KepModel
import KepPlantUML

extension AppSession {

    // MARK: - Open / close / new

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    /// Open a file by URL — focuses an existing tab if one already shows it,
    /// otherwise loads + adds + activates + arms the file watcher + bumps
    /// the recents list.
    /// Open `url`. Obsidian-style: a plain open REUSES the active tab (replaces
    /// its document) so browsing the file tree doesn't spawn a tab per click;
    /// new tabs are explicit (`inNewTab: true`, e.g. the sidebar's "Open in New
    /// Tab"). A file already open just gets activated; the active tab is never
    /// replaced when it has unsaved changes (its work is preserved in a tab).
    func open(url: URL, inNewTab: Bool = false, focusEditor: Bool = true) {
        pendingEditorFocus = focusEditor
        if let existing = openDocuments.first(where: { $0.fileURL == url }) {
            activeDocumentID = existing.id
            persistOpenTabs()
            return
        }
        let doc: OpenDocument
        do {
            doc = try OpenDocument.load(from: url)
        } catch {
            lastError = String(format: L("error.open_failed"), error.localizedDescription)
            return
        }
        if !inNewTab,
           let activeID = activeDocumentID,
           let idx = openDocuments.firstIndex(where: { $0.id == activeID }),
           !openDocuments[idx].isDirty {
            // Reuse the active tab — swap its document out in place.
            stopFileWatcher(for: openDocuments[idx].id)
            tabManager.remove(openDocuments[idx].id)
            openDocuments[idx] = doc
        } else {
            openDocuments.append(doc)
        }
        activeDocumentID = doc.id
        startFileWatcher(for: doc)
        CollectionStore.shared.touch(url: url)
        persistOpenTabs()
    }

    func newMindMap() {
        let map = MindMap()
        map.root = Topic(text: "New Mind Map")
        // Obsidian-style: write a real file straight into the workspace and
        // inline-rename it — no save panel. Only fall back to an in-memory,
        // save-later doc when there's no workspace folder to put it in.
        if let folder = defaultCreationFolder() {
            createDocumentOnDisk(extension: "mmd", in: folder, starter: Data(map.write().utf8))
        } else {
            let doc = OpenDocument(kind: .mindMap(map), fileURL: nil, title: "Untitled.mmd")
            openDocuments.append(doc)
            activeDocumentID = doc.id
        }
    }

    /// Open a fresh, untitled text-backed document (markdown / csv / plantuml /
    /// plain text). Save (⌘S) prompts for a path since fileURL is nil.
    func newTextDocument(_ type: SupportedFileType) {
        if let folder = defaultCreationFolder() {
            createDocumentOnDisk(extension: type.rawValue, in: folder)
        } else {
            let doc = OpenDocument(kind: .text("", fileType: type), fileURL: nil,
                                   title: "Untitled.\(type.rawValue)")
            openDocuments.append(doc)
            activeDocumentID = doc.id
        }
    }

    func newMarkdown() { newTextDocument(.markdown) }
    func newCSV()      { newTextDocument(.csv) }
    func newTextFile() { newTextDocument(.plainText) }

    /// New Research Notebook (.mnb) — a markdown-on-disk notebook seeded with a
    /// heading so it's never zero-byte (mirrors newPlantUML's starter).
    func newResearchNotebook() {
        let starter = "# New Research Notebook\n"
        if let folder = defaultCreationFolder() {
            createDocumentOnDisk(extension: SupportedFileType.mindNotebook.rawValue,
                                 in: folder, starter: Data(starter.utf8))
        } else {
            let doc = OpenDocument(kind: .text(starter, fileType: .mindNotebook), fileURL: nil,
                                   title: "Untitled.\(SupportedFileType.mindNotebook.rawValue)")
            openDocuments.append(doc)
            activeDocumentID = doc.id
        }
    }

    /// New PlantUML doc — first present the template picker (javamind parity:
    /// 19 diagram scaffolds) instead of dropping the user into an empty file.
    func newPlantUML() { plantUMLTemplatePickerOpen = true }

    /// Create a `.puml` seeded with `template`'s body (called by the picker).
    func createPlantUML(from template: PlantUMLTemplate) {
        let starter = Data(template.body.utf8)
        if let folder = defaultCreationFolder() {
            createDocumentOnDisk(extension: SupportedFileType.plantUML.rawValue, in: folder, starter: starter)
        } else {
            let doc = OpenDocument(kind: .text(template.body, fileType: .plantUML), fileURL: nil,
                                   title: "Untitled.\(SupportedFileType.plantUML.rawValue)")
            openDocuments.append(doc)
            activeDocumentID = doc.id
        }
    }

    /// Open a fresh UNTITLED document in its OWN new tab, held in memory (no file
    /// is written to the workspace until ⌘S). This is what the tab-bar "+" uses:
    /// it spins up a new doc *view*, which is what users expect from a tab "+",
    /// rather than dropping a real file into the current workspace folder the way
    /// File ▸ New does. Focuses the new editor.
    func newDocViewTab(_ type: SupportedFileType) {
        let doc: OpenDocument
        switch type {
        case .mindMap:
            let map = MindMap()
            map.root = Topic(text: "New Mind Map")
            doc = OpenDocument(kind: .mindMap(map), fileURL: nil, title: "Untitled.mmd")
        case .mindNotebook:
            doc = OpenDocument(kind: .text("# New Research Notebook\n", fileType: .mindNotebook),
                               fileURL: nil, title: "Untitled.mnb")
        default:
            doc = OpenDocument(kind: .text("", fileType: type),
                               fileURL: nil, title: "Untitled.\(type.rawValue)")
        }
        openDocuments.append(doc)
        pendingEditorFocus = true
        activeDocumentID = doc.id
        persistOpenTabs()
    }

    func closeActive() {
        // ⌘W on a non-document window (Settings, About, …) closes that window
        // natively — only redirect when we KNOW the key window is the document
        // window (host known and matching).
        if let host = WindowWidthKeeper.shared.hostWindow,
           let key = NSApp.keyWindow, key !== host {
            key.performClose(nil)
            return
        }
        // Document window: close the active tab if there is one; otherwise no-op
        // so the window stays open even with no active document.
        guard let id = activeDocumentID else { return }
        closeTab(id)
    }

    /// Close a single tab by id. When the tab has unsaved changes, prompt
    /// Save / Discard / Cancel first so ⌘W can't silently throw work away
    /// (#178). Switches active to the next available when the closed tab was
    /// active.
    func closeTab(_ id: OpenDocument.ID) {
        guard let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        if openDocuments[idx].isDirty {
            switch promptDirtyClose(titles: [openDocuments[idx].title]) {
            case .cancel:
                return
            case .save:
                // A failed / cancelled save must abort the close — never
                // discard the buffer behind the user's back.
                guard saveDocument(at: idx) else { return }
            case .discard:
                break
            }
        }
        performClose(id)
        persistOpenTabs()
    }

    /// Close every tab except the one with `keep`.
    func closeOtherTabs(keep id: OpenDocument.ID) {
        closeMany(openDocuments.map(\.id).filter { $0 != id })
    }

    /// Close every open tab.
    func closeAllTabs() {
        closeMany(openDocuments.map(\.id))
    }

    /// Close a batch of tabs with a single combined dirty-changes prompt
    /// rather than one alert per tab. Save All saves each dirty doc (aborting
    /// the whole batch if any save fails/cancels); Discard All closes them
    /// regardless; Cancel leaves everything open.
    private func closeMany(_ ids: [OpenDocument.ID]) {
        let dirtyIdx = ids.compactMap { id in
            openDocuments.firstIndex(where: { $0.id == id && $0.isDirty })
        }
        if !dirtyIdx.isEmpty {
            switch promptDirtyClose(titles: dirtyIdx.map { openDocuments[$0].title }) {
            case .cancel:
                return
            case .save:
                for idx in dirtyIdx where openDocuments.indices.contains(idx) {
                    guard saveDocument(at: idx) else { return }
                }
            case .discard:
                break
            }
        }
        for id in ids { performClose(id) }
        persistOpenTabs()
    }

    /// The bookkeeping half of closing a tab — stop its watcher, drop it from
    /// the model + tab manager, retarget the active tab. No prompting,
    /// no persistence (callers batch the persist).
    private func performClose(_ id: OpenDocument.ID) {
        guard let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        stopFileWatcher(for: id)
        openDocuments.remove(at: idx)
        tabManager.remove(id)
        if activeDocumentID == id {
            activeDocumentID = tabManager.activeID ?? openDocuments.last?.id
        }
    }

    /// Show the Save / Discard / Cancel alert for one or more dirty documents.
    /// `titles` drives the message; a single entry names the file, several get
    /// a count. Returns the user's `DirtyCloseChoice`.
    private func promptDirtyClose(titles: [String]) -> DirtyCloseChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if titles.count == 1 {
            alert.messageText = String(format: L("close.dirty.title"), titles[0])
        } else {
            alert.messageText = String(format: L("close.dirty.title_many"), titles.count)
        }
        alert.informativeText = L("close.dirty.message")
        alert.addButton(withTitle: titles.count == 1 ? L("close.dirty.save")
                                                      : L("close.dirty.save_all"))
        alert.addButton(withTitle: L("close.dirty.cancel"))
        alert.addButton(withTitle: titles.count == 1 ? L("close.dirty.discard")
                                                      : L("close.dirty.discard_all"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .save
        case .alertThirdButtonReturn:  return .discard
        default:                       return .cancel
        }
    }

    func cycleNextTab() {
        guard let current = activeDocumentID else { return }
        if let next = tabManager.nextMRU(after: current) {
            pendingEditorFocus = true   // a deliberate switch focuses the editor
            activeDocumentID = next
            persistOpenTabs()
        }
    }

    func cyclePreviousTab() {
        guard let current = activeDocumentID else { return }
        if let prev = tabManager.previousMRU(before: current) {
            pendingEditorFocus = true   // a deliberate switch focuses the editor
            activeDocumentID = prev
            persistOpenTabs()
        }
    }

    /// Open a FreeMind/Freeplane .mm file via NSOpenPanel, parse it, and present
    /// it as a fresh in-memory mindmap document (no fileURL, so Save will
    /// prompt for a .mmd path).
    func importFreemind() {
        importMindMap(extension: "mm") { url in
            let xml = try String(contentsOf: url, encoding: .utf8)
            return try FreemindImporter.parse(xml)
        }
    }

    /// Import an indented-text outline (one topic per line, indent = nesting).
    func importTextOutline() {
        importMindMap(extension: "txt") { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return try TextOutlineImporter.parse(text)
        }
    }

    /// Import a Mindmup `.mup` JSON document.
    func importMindmup() {
        importMindMap(extension: "mup") { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return try MindmupImporter.parse(text)
        }
    }

    /// Import a Coggle `.mm` XML export.
    func importCoggle() {
        importMindMap(extension: "mm") { url in
            let xml = try String(contentsOf: url, encoding: .utf8)
            return try CoggleImporter.parse(xml)
        }
    }

    /// Import a modern XMind (Zen) `.xmind` bundle (a ZIP with content.json).
    func importXMind() {
        importMindMap(extension: "xmind") { url in
            let data = try Data(contentsOf: url)
            return try XMindImporter.parse(data: data)
        }
    }

    /// Import a Novamind `.nm5` bundle (a ZIP with content.xml).
    func importNovamind() {
        importMindMap(extension: "nm5") { url in
            let data = try Data(contentsOf: url)
            return try NovamindImporter.parse(data: data)
        }
    }

    /// Shared scaffolding for any mindmap importer: open panel scoped to one
    /// extension, parse via the supplied closure, present as an untitled
    /// .mmd doc. Errors route to lastError.
    private func importMindMap(extension ext: String, parse: (URL) throws -> MindMap) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: ext) ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let map = try parse(url)
            let title = url.deletingPathExtension().lastPathComponent + ".mmd"
            let doc = OpenDocument(kind: .mindMap(map), fileURL: nil, title: title)
            openDocuments.append(doc)
            activeDocumentID = doc.id
        } catch {
            lastError = String(format: L("error.open_failed"), error.localizedDescription)
        }
    }

    // MARK: - File watching

    func startFileWatcher(for doc: OpenDocument) {
        guard let url = doc.fileURL else { return }
        let id = doc.id
        let watcher = FileWatcher(url: url) { [weak self] event in
            guard let self else { return }
            self.handleFileWatcherEvent(event, for: id)
        }
        if watcher.start() { fileWatchers[id] = watcher }
    }

    func handleFileWatcherEvent(_ event: DispatchSource.FileSystemEvent, for id: OpenDocument.ID) {
        guard let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        if event.contains(.delete) || event.contains(.rename) {
            openDocuments[idx].hasExternalChanges = true
            return
        }
        // Plain write. When the doc has unsaved local edits, prompt instead
        // of clobbering them; otherwise the silent reload is fine and the
        // orange dot just records that an external write happened.
        openDocuments[idx].hasExternalChanges = true
        if openDocuments[idx].isDirty {
            promptExternalChangeConflict(for: id)
        } else {
            reloadFromDisk(at: idx)
        }
    }

    /// Replace the open doc's payload with the on-disk content. Clears the
    /// dirty + external-change flags on success.
    private func reloadFromDisk(at idx: Int) {
        guard let url = openDocuments[idx].fileURL,
              let reloaded = try? OpenDocument.load(from: url) else { return }
        openDocuments[idx].kind = reloaded.kind
        openDocuments[idx].title = reloaded.title
        openDocuments[idx].isDirty = false
        openDocuments[idx].hasExternalChanges = false
    }

    /// Public entry point for the tab right-click "Reload from Disk" menu
    /// item. Looks up by id then delegates to `reloadFromDisk(at:)`.
    func reloadTab(_ id: OpenDocument.ID) {
        guard let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        reloadFromDisk(at: idx)
    }

    /// Three-way prompt when the on-disk file changed under us *and* there
    /// are unsaved local edits. Mirrors what mindolph-fx's MainController
    /// does for the same situation. Caller must be on the main thread —
    /// FileWatcher delivers on .main by default so this is satisfied.
    private func promptExternalChangeConflict(for id: OpenDocument.ID) {
        guard let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        let doc = openDocuments[idx]
        let alert = NSAlert()
        alert.messageText = String(format: L("conflict.title"), doc.title)
        alert.informativeText = L("conflict.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("conflict.button.reload"))
        alert.addButton(withTitle: L("conflict.button.keep_mine"))
        alert.addButton(withTitle: L("conflict.button.save_mine"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:    // Reload from disk — discard local edits
            reloadFromDisk(at: idx)
        case .alertSecondButtonReturn:   // Keep mine — leave buffer alone, isDirty stays
            openDocuments[idx].hasExternalChanges = true
        case .alertThirdButtonReturn:    // Save mine over the external write
            if let url = doc.fileURL {
                do {
                    try doc.save(to: url)
                    openDocuments[idx].isDirty = false
                    openDocuments[idx].hasExternalChanges = false
                } catch {
                    lastError = String(format: L("error.save_failed"), error.localizedDescription)
                }
            }
        default: break
        }
    }

    func stopFileWatcher(for id: OpenDocument.ID) {
        fileWatchers[id]?.stop()
        fileWatchers.removeValue(forKey: id)
    }
}
