import AppKit
import MindoCore

extension AppSession {

    func saveActiveTabsAsCollection() {
        let openURLs = openDocuments.compactMap(\.fileURL)
        guard !openURLs.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = L("collections.save_prompt.title")
        alert.informativeText = L("collections.save_prompt.message")
        let field = NSTextField(string: defaultCollectionName())
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L("collections.save_prompt.confirm"))
        alert.addButton(withTitle: L("collections.save_prompt.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = CollectionStore.shared.addCollection(name: name, fileURLs: openURLs)
    }

    func openCollection(_ collection: FileCollection) {
        // Close tabs without on-disk backing only — preserve unsaved scratch
        // documents (rare but possible).
        for doc in openDocuments where doc.fileURL != nil {
            stopFileWatcher(for: doc.id)
            tabManager.remove(doc.id)
        }
        openDocuments.removeAll { $0.fileURL != nil }
        for url in collection.fileURLs {
            open(url: url)
        }
    }

    func clearRecents() {
        CollectionStore.shared.clearRecents()
    }

    func defaultCollectionName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "Tabs \(formatter.string(from: Date()))"
    }
}
