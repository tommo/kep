import AppKit
import UniformTypeIdentifiers
import MindoMarkdown

extension AppSession {

    func saveActive() {
        guard let doc = activeDocument else { return }
        if let url = doc.fileURL {
            do { try doc.save(to: url) }
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
            } catch {
                lastError = String(format: L("error.save_failed"), error.localizedDescription)
            }
        }
    }

    /// Pull the active doc's markdown text and write it as standalone HTML.
    @MainActor
    func exportActiveAsHTML() async {
        guard let doc = activeDocument, case .text(let body, .markdown) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "html") ?? .data]
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MarkdownExporter.exportHTML(markdown: body, to: url)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }

    /// Render the active doc's markdown to PDF via the offscreen WKWebView.
    @MainActor
    func exportActiveAsPDF() async {
        guard let doc = activeDocument, case .text(let body, .markdown) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "pdf") ?? .data]
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await MarkdownExporter.exportPDF(markdown: body, to: url)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }
}
