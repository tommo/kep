import AppKit
import SwiftUI
import KepCSV
import KepMarkdown
import KepMindMap
import KepPlantUML

/// Routes the active document to the right editor view based on `kind`.
struct EditorPane: View {
    @Binding var session: AppSession
    let documentID: OpenDocument.ID
    let theme: MindMapTheme
    @Environment(\.colorScheme) private var colorScheme

    private var documentIndex: Int? {
        session.openDocuments.firstIndex { $0.id == documentID }
    }

    var body: some View {
        Group {
            if let idx = documentIndex {
                content(for: session.openDocuments[idx])
            } else {
                EmptyView()
            }
        }
        // Stretch every editor to the available area. Without this NSViewRepresentable
        // wrappers (NSScrollView around MindMapView, the markdown / plantuml / csv
        // splits) fall back to their small intrinsic content sizes — bug #38.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for document: OpenDocument) -> some View {
        switch document.kind {
        case .mindMap(let map):
            MindMapCanvas(
                    map: map,
                    theme: theme,
                    onChange: { _ in markDirty(documentID) },
                    onExtraFileTap: { url in session.open(url: url) },
                    onOpenWikiLink: { target, heading in session.openWikiLink(target: target, heading: heading) },
                    navigationTarget: session.sanitizedNavigationTarget,
                    searchHighlight: session.lastSearchMatch,
                    onSelectionPath: { path in session.selectedOutlineTarget = path },
                    shouldAutoFocus: { session.pendingEditorFocus },
                    onDidAutoFocus: { session.pendingEditorFocus = false },
                    // Persist zoom / pan / selection per saved file (skipped for
                    // untitled docs, which have no path to key on).
                    loadViewState: {
                        guard let path = documentPath() else { return nil }
                        return session.canvasViewState(forPath: path)
                    },
                    saveViewState: { state in
                        guard let path = documentPath() else { return }
                        session.setCanvasViewState(state, forPath: path)
                    }
                )
            .overlay(alignment: .top) {
                // Float the find bar OVER the canvas so opening it never
                // reflows / resizes the graph (it has its own material bg).
                if session.inDocFindOpen, let view = activeMindMapView() {
                    MindMapFindBar(view: view) { session.inDocFindOpen = false }
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
            }
            .onChange(of: session.zoomCommandTick) { _, _ in
                // The canvas is created lazily inside MindMapCanvas; we route
                // zoom commands by walking the App's window's content tree
                // for an NSScrollView whose document is a MindMapView.
                guard let win = NSApp.keyWindow else { return }
                if let scroll = win.contentView?.firstSubview(ofType: NSScrollView.self,
                                                              where: { $0.documentView is MindMapView }) {
                    switch session.zoomCommand {
                    case .in:    MindMapCanvas.zoom(scroll, by: 1.25)
                    case .out:   MindMapCanvas.zoom(scroll, by: 1.0 / 1.25)
                    case .reset: MindMapCanvas.resetZoom(scroll)
                    case .fit:   MindMapCanvas.fitToViewport(scroll)
                    }
                }
            }
            .onChange(of: session.mindmapCommandTick) { _, _ in
                guard let win = NSApp.keyWindow,
                      let scroll = win.contentView?.firstSubview(ofType: NSScrollView.self,
                                                                  where: { $0.documentView is MindMapView }),
                      let view = scroll.documentView as? MindMapView else { return }
                switch session.mindmapCommand {
                case .foldAll:   view.setAllCollapsed(true)
                case .unfoldAll: view.setAllCollapsed(false)
                case .redraw:    view.needsDisplay = true
                case .reload:    view.rebuildElementsPublic(); view.needsDisplay = true
                }
            }
        case .text(_, .markdown):
            MarkdownEditor(
                text: textBinding(for: documentID),
                isDarkMode: colorScheme == .dark,
                navigationTarget: session.sanitizedNavigationTarget,
                documentURL: session.openDocuments.first(where: { $0.id == documentID })?.fileURL,
                wikiLinkCandidates: { session.wikiLinkDocumentNames() },
                onOpenWikiLink: { target, heading in session.openWikiLink(target: target, heading: heading) }
            )
        case .text(_, .plantUML):
            PlantUMLEditor(
                text: textBinding(for: documentID),
                isDarkMode: colorScheme == .dark,
                documentURL: session.openDocuments.first(where: { $0.id == documentID })?.fileURL,
                navigationTarget: session.sanitizedNavigationTarget
            )
        case .text(_, .csv):
            // Grid on top; the dedicated block editor docks below it (when a
            // block is selected in the inspector). CSVEditor stays the first
            // child so its NSView identity is stable across drawer show/hide.
            VStack(spacing: 0) {
                CSVEditor(text: textBinding(for: documentID),
                          findBarVisible: $session.csvFindOpen,
                          documentURL: session.openDocuments.first(where: { $0.id == documentID })?.fileURL,
                          onBlocksModel: { session.activeCSVBlocks = $0 },
                          onLiveBridge: { url, bridge in session.registerLiveCSV(url, bridge) })
                if let blocks = session.activeCSVBlocks {
                    CSVBlockEditor(model: blocks, isDark: colorScheme == .dark)
                }
            }
        case .text(_, .mindNotebook):
            // LOAD-BEARING: must precede the `.text(let body, _)` catch-all
            // below — Swift matches top-down, else .mnb falls through to the
            // read-only view.
            NotebookEditor(
                text: textBinding(for: documentID),
                documentURL: session.openDocuments.first(where: { $0.id == documentID })?.fileURL,
                isDarkMode: colorScheme == .dark,
                runOne: { src, ctx in await session.runNotebookCell(src, in: ctx) },
                runAll: { nb, ctx in await session.runNotebookAll(nb, in: ctx) },
                runAgent: { question, context, ctx, sink in await session.runNotebookAgent(question, context: context, in: ctx, into: sink) },
                onOpenSource: { name in session.openWikiLink(target: name, heading: nil) },
                shouldFocusOnAppear: { session.pendingEditorFocus })
        case .text(_, .lua):
            // Notebook-library Lua (notebook.lua / lib/*.lua): editable, with the
            // same Lua syntax highlighting as notebook code cells.
            LuaSourceEditor(text: textBinding(for: documentID), isDark: colorScheme == .dark)
        case .text(let body, _):
            ScrollView {
                Text(body)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        case .unsupported(let path):
            if ImageFileView.isImagePath(path) {
                ImageFileView(url: URL(fileURLWithPath: path))
            } else {
                VStack {
                    Image(systemName: "doc.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text(L("plantuml.unsupported.unsupported_file_type"))
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func textBinding(for id: OpenDocument.ID) -> Binding<String> {
        Binding(
            get: {
                guard let idx = session.openDocuments.firstIndex(where: { $0.id == id }) else { return "" }
                if case .text(let s, _) = session.openDocuments[idx].kind { return s }
                return ""
            },
            set: { newValue in
                guard let idx = session.openDocuments.firstIndex(where: { $0.id == id }) else { return }
                if case .text(let prev, let t) = session.openDocuments[idx].kind {
                    session.openDocuments[idx].kind = .text(newValue, fileType: t)
                    if newValue != prev { session.openDocuments[idx].isDirty = true }
                }
            }
        )
    }

    /// On-disk path of the active document, used to key its persisted canvas
    /// view state. nil for untitled (unsaved) documents.
    private func documentPath() -> String? {
        session.openDocuments.first(where: { $0.id == documentID })?.fileURL?.path
    }

    private func markDirty(_ id: OpenDocument.ID) {
        guard let idx = session.openDocuments.firstIndex(where: { $0.id == id }) else { return }
        session.openDocuments[idx].isDirty = true
    }

    /// Walk the key window's view tree to find the active MindMapView.
    /// Same trick the zoom-routing path uses — gives the find bar direct
    /// access to the AppKit canvas without exposing it through SwiftUI
    /// state.
    private func activeMindMapView() -> MindMapView? {
        guard let win = NSApp.keyWindow,
              let scroll = win.contentView?.firstSubview(ofType: NSScrollView.self, where: { $0.documentView is MindMapView })
        else { return nil }
        return scroll.documentView as? MindMapView
    }
}
