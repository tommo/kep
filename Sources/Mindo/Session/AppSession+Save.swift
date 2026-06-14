import AppKit
import UniformTypeIdentifiers
import MindoBase
import MindoCore
import MindoMarkdown
import MindoMindMap
import MindoModel

extension AppSession {

    /// Save dirty docs that already have a file path on tab switch / window
    /// blur. Skips untitled docs (would otherwise pop a Save panel mid-blur,
    /// which is hostile UX) and respects the PrefKeys.autosaveOnBlur toggle.
    /// Stays silent on errors — failure surfaces via the next manual save.
    func autosaveDocument(id: OpenDocument.ID) {
        guard PrefKeys.bool(PrefKeys.autosaveOnBlur, fallback: true) else { return }
        guard let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        let doc = openDocuments[idx]
        guard Autosave.shouldAutosave(
            isDirty: doc.isDirty,
            hasFileURL: doc.fileURL != nil,
            isSavable: doc.isAutosavable
        ), let url = doc.fileURL else { return }
        do {
            try doc.save(to: url)
            openDocuments[idx].isDirty = false
            openDocuments[idx].hasExternalChanges = false
        } catch {
            // Swallow — the user will see the dirty flag and can ⌘S manually.
        }
    }

    /// Run autosave across every open doc. Wired to NSWindow.didResignKey so
    /// switching to another app commits work-in-progress.
    func autosaveAllDirty() {
        guard PrefKeys.bool(PrefKeys.autosaveOnBlur, fallback: true) else { return }
        for doc in openDocuments {
            autosaveDocument(id: doc.id)
        }
    }

    /// Explicit Save All — saves every dirty doc that already has a
    /// file URL. Untitled docs are skipped (would otherwise pop a
    /// modal Save panel for each one, which is hostile UX); the user
    /// can save those individually with ⌘S. Surfaces the *first*
    /// failure via lastError but keeps trying the rest so a single
    /// permission glitch doesn't abandon the others.
    @MainActor
    func saveAllDirty() {
        var firstError: String?
        for idx in openDocuments.indices {
            let doc = openDocuments[idx]
            guard doc.isDirty, let url = doc.fileURL else { continue }
            do {
                try doc.save(to: url)
                openDocuments[idx].isDirty = false
                openDocuments[idx].hasExternalChanges = false
            } catch {
                if firstError == nil {
                    firstError = String(format: L("error.save_failed"), error.localizedDescription)
                }
            }
        }
        if let firstError { lastError = firstError }
    }

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
        // Default to the active doc's parent dir when it has one — saves the
        // user from re-navigating to the workspace on every Save As.
        if let url = doc.fileURL {
            panel.directoryURL = url.deletingLastPathComponent()
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

    /// Export the active mindmap as a PNG raster.
    @MainActor
    func exportActiveAsPNG() {
        exportActiveMindmapImage(extension: "png") { map, url in
            try MindMapImageExport.exportPNG(map, theme: theme.theme, to: url)
        }
    }

    /// Export the active mindmap as an SVG vector image.
    @MainActor
    func exportActiveAsSVG() {
        exportActiveMindmapImage(extension: "svg") { map, url in
            try MindMapImageExport.exportSVG(map, theme: theme.theme, to: url)
        }
    }

    /// Export the active mindmap as a vector PDF page. Distinct from the
    /// markdown PDF exporter (`exportActiveAsPDF`) which uses WKWebView.
    @MainActor
    func exportActiveMindmapAsPDF() {
        exportActiveMindmapImage(extension: "pdf") { map, url in
            try MindMapImageExport.exportPDF(map, theme: theme.theme, to: url)
        }
    }

    /// File > Print (⌘P). For mindmap docs, builds an NSPrintOperation from
    /// the offscreen MindMapView so the printed page snaps to content.
    /// For text-based docs, dispatches the standard `printDocument:`
    /// selector down the responder chain — NSTextView and WKWebView both
    /// honour it via their built-in handlers.
    @MainActor
    func printActiveDocument() {
        guard let doc = activeDocument else { return }
        switch doc.kind {
        case .mindMap(let map):
            do {
                let op = try MindMapImageExport.printOperation(map, theme: theme.theme)
                op.run()
            } catch {
                lastError = String(format: L("error.save_failed"), error.localizedDescription)
            }
        case .text, .unsupported:
            // The focused NSTextView / WKWebView prints itself via the
            // responder chain. MUST be `print:` — the old `printDocument:`
            // is an NSDocument method these NSView responders don't
            // implement, so ⌘P silently did nothing.
            TextDocumentPrinting.printFirstResponder()
        }
    }

    @MainActor
    private func exportActiveMindmapImage(extension ext: String, write: (MindMap, URL) throws -> Void) {
        guard let doc = activeDocument, case .mindMap(let map) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: ext) ?? .data]
        if let url = doc.fileURL { panel.directoryURL = url.deletingLastPathComponent() }
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + "." + ext
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try write(map, url) }
        catch { lastError = String(format: L("error.save_failed"), error.localizedDescription) }
    }

    /// Export the active mindmap as Org-Mode text.
    @MainActor
    func exportActiveAsOrgMode() {
        guard let doc = activeDocument, case .mindMap(let map) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "org") ?? .data]
        if let url = doc.fileURL { panel.directoryURL = url.deletingLastPathComponent() }
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".org"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try OrgModeExporter.export(map).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }

    // MARK: - Copy mindmap to pasteboard (mindolph parity — doExportToClipboard)

    /// Run `convert` on the active mindmap and put the result on the
    /// general pasteboard as a string. Silent no-op when the front
    /// document isn't a mindmap so the menu items can stay enabled
    /// without surprising the user with errors.
    @MainActor
    private func copyActiveMindmap(_ convert: (MindMap) -> String) {
        guard let doc = activeDocument, case .mindMap(let map) = doc.kind else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(convert(map), forType: .string)
    }

    @MainActor func copyActiveMindmapAsMarkdown() { copyActiveMindmap(MindMapMarkdownExporter.export) }
    @MainActor func copyActiveMindmapAsAsciiDoc() { copyActiveMindmap(AsciiDocExporter.export) }
    @MainActor func copyActiveMindmapAsOrgMode()  { copyActiveMindmap(OrgModeExporter.export) }
    @MainActor func copyActiveMindmapAsText()     { copyActiveMindmap(PlainTextExporter.export) }

    /// Export the active mindmap as a Mindmup `.mup` JSON document
    /// (mindolph parity — MindmupExporter).
    @MainActor
    func exportActiveAsMindmup() {
        guard let doc = activeDocument, case .mindMap(let map) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "mup") ?? .data]
        if let url = doc.fileURL { panel.directoryURL = url.deletingLastPathComponent() }
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".mup"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MindmupExporter.export(map).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }

    /// Export the active mindmap as AsciiDoc (mindolph parity —
    /// ASCIIDocExporter).
    @MainActor
    func exportActiveAsAsciiDoc() {
        guard let doc = activeDocument, case .mindMap(let map) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "adoc") ?? .data]
        if let url = doc.fileURL { panel.directoryURL = url.deletingLastPathComponent() }
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".adoc"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AsciiDocExporter.export(map).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }

    /// Export the active mindmap as Markdown (mindolph parity — the
    /// MarkdownExporter / ConvertUtils.convertTopics path). Top 5
    /// levels become `#`..`#####` headings; deeper levels become
    /// indented bullets.
    @MainActor
    func exportActiveAsMarkdown() {
        guard let doc = activeDocument, case .mindMap(let map) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "md") ?? .data]
        if let url = doc.fileURL { panel.directoryURL = url.deletingLastPathComponent() }
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MindMapMarkdownExporter.export(map).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }

    /// Export the active mindmap as a FreeMind .mm file. NSSavePanel defaults
    /// to the doc's stem + .mm; serialization is synchronous.
    @MainActor
    func exportActiveAsFreeMind() {
        guard let doc = activeDocument, case .mindMap(let map) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "mm") ?? .data]
        if let url = doc.fileURL { panel.directoryURL = url.deletingLastPathComponent() }
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
        if let url = doc.fileURL { panel.directoryURL = url.deletingLastPathComponent() }
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + "." + ext
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await write(body, url)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }
}
