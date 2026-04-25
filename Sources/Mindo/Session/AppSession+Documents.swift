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
            return
        }
        do {
            let doc = try OpenDocument.load(from: url)
            openDocuments.append(doc)
            activeDocumentID = doc.id
            startFileWatcher(for: doc)
            CollectionStore.shared.touch(url: url)
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
    }

    func cycleNextTab() {
        guard let current = activeDocumentID else { return }
        if let next = tabManager.nextMRU(after: current) {
            activeDocumentID = next
        }
    }

    func cyclePreviousTab() {
        guard let current = activeDocumentID else { return }
        if let prev = tabManager.previousMRU(before: current) {
            activeDocumentID = prev
        }
    }

    /// Open a FreeMind/Freeplane .mm file via NSOpenPanel, parse it, and present
    /// it as a fresh in-memory mindmap document (no fileURL, so Save will
    /// prompt for a .mmd path).
    func importFreemind() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "mm") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let xml = try String(contentsOf: url, encoding: .utf8)
            let map = try FreemindImporter.parse(xml)
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
        // Plain write — pull the new content into the existing document slot.
        // Keep the same OpenDocument.id so tab routing + watcher mapping
        // stay valid. We don't yet thread editor dirty-state up to the
        // App layer, so the reload always wins; the orange dot still
        // surfaces the fact that an external write happened.
        openDocuments[idx].hasExternalChanges = true
        guard let url = openDocuments[idx].fileURL,
              let reloaded = try? OpenDocument.load(from: url) else { return }
        openDocuments[idx].kind = reloaded.kind
        openDocuments[idx].title = reloaded.title
    }

    func stopFileWatcher(for id: OpenDocument.ID) {
        fileWatchers[id]?.stop()
        fileWatchers.removeValue(forKey: id)
    }
}
