import AppKit
import UniformTypeIdentifiers
import MindoMarkdown
import MindoModel

extension AppSession {

    func saveActive() {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        let doc = openDocuments[idx]
        if let url = doc.fileURL {
            do {
                try doc.save(to: url)
                openDocuments[idx].isDirty = false
                openDocuments[idx].hasExternalChanges = false
            }
            catch { lastError = "Save failed: \(error.localizedDescription)" }
        } else {
            saveActiveAs()
        }
    }

    func saveActiveAs() {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        let doc = openDocuments[idx]
        let panel = NSSavePanel()
        if let ext = doc.kind.preferredExtension {
            panel.allowedContentTypes = [UTType.init(filenameExtension: ext) ?? .data]
        }
        panel.nameFieldStringValue = doc.title.isEmpty ? L("picker.untitled_mindmap") : doc.title
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try doc.save(to: url)
                openDocuments[idx].fileURL = url
                openDocuments[idx].title = url.lastPathComponent
                openDocuments[idx].isDirty = false
                openDocuments[idx].hasExternalChanges = false
            } catch {
                lastError = String(format: L("error.save_failed"), error.localizedDescription)
            }
        }
    }

    /// Pull the active doc's markdown text and write it as standalone HTML.
    @MainActor
    func exportActiveAsHTML() async {
        await exportActiveMarkdown(extension: "html") { body, url in
            try MarkdownExporter.exportHTML(markdown: body, to: url)
        }
    }

    /// Render the active doc's markdown to PDF via the offscreen WKWebView.
    @MainActor
    func exportActiveAsPDF() async {
        await exportActiveMarkdown(extension: "pdf") { body, url in
            try await MarkdownExporter.exportPDF(markdown: body, to: url)
        }
    }

    /// Export the active mindmap as a FreeMind .mm file. NSSavePanel defaults
    /// to the doc's stem + .mm; serialization is synchronous.
    @MainActor
    func exportActiveAsFreeMind() {
        guard let doc = activeDocument, case .mindMap(let map) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "mm") ?? .data]
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".mm"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FreemindExporter.export(map).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }

    /// Shared scaffolding for HTML / PDF export of the active markdown doc:
    /// pulls the body, runs an NSSavePanel, then hands the body+url to the
    /// exporter and routes any thrown error to `lastError`.
    @MainActor
    private func exportActiveMarkdown(
        extension ext: String,
        write: (String, URL) async throws -> Void
    ) async {
        guard let doc = activeDocument, case .text(let body, .markdown) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: ext) ?? .data]
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + "." + ext
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await write(body, url)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }
}
