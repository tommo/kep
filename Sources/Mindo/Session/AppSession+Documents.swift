import AppKit
import UniformTypeIdentifiers
import MindoCore
import MindoModel

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
    func open(url: URL) {
        if let existing = openDocuments.first(where: { $0.fileURL == url }) {
            activeDocumentID = existing.id
            persistOpenTabs()
            return
        }
        do {
            let doc = try OpenDocument.load(from: url)
            openDocuments.append(doc)
            activeDocumentID = doc.id
            startFileWatcher(for: doc)
            CollectionStore.shared.touch(url: url)
            persistOpenTabs()
        } catch {
            lastError = String(format: L("error.open_failed"), error.localizedDescription)
        }
    }

    func newMindMap() {
        let map = MindMap()
        map.root = Topic(text: "New Mind Map")
        let doc = OpenDocument(kind: .mindMap(map), fileURL: nil, title: "Untitled.mmd")
        openDocuments.append(doc)
        activeDocumentID = doc.id
    }

    func closeActive() {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        stopFileWatcher(for: id)
        openDocuments.remove(at: idx)
        tabManager.remove(id)
        activeDocumentID = tabManager.activeID ?? openDocuments.last?.id
        persistOpenTabs()
    }

    func cycleNextTab() {
        guard let current = activeDocumentID else { return }
        if let next = tabManager.nextMRU(after: current) {
            activeDocumentID = next
            persistOpenTabs()
        }
    }

    func cyclePreviousTab() {
        guard let current = activeDocumentID else { return }
        if let prev = tabManager.previousMRU(before: current) {
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
