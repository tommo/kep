import AppKit
import SwiftUI
import MindoCSV
import MindoMarkdown
import MindoMindMap
import MindoPlantUML

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
            VStack(spacing: 0) {
                if session.inDocFindOpen, let view = activeMindMapView() {
                    MindMapFindBar(view: view) { session.inDocFindOpen = false }
                    Divider()
                }
                MindMapCanvas(
                    map: map,
                    theme: theme,
                    onChange: { _ in markDirty(documentID) },
                    onExtraFileTap: { url in session.open(url: url) },
                    navigationTarget: session.sanitizedNavigationTarget
                )
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
                }
            }
        case .text(_, .markdown):
            MarkdownEditor(
                text: textBinding(for: documentID),
                isDarkMode: colorScheme == .dark,
                navigationTarget: session.sanitizedNavigationTarget
            )
        case .text(_, .plantUML):
            PlantUMLEditor(
                text: textBinding(for: documentID),
                isDarkMode: colorScheme == .dark
            )
        case .text(_, .csv):
            CSVEditor(text: textBinding(for: documentID))
        case .text(let body, _):
            ScrollView {
                Text(body)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        case .unsupported(let path):
            VStack {
                Image(systemName: "doc.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                Text(L("plantuml.unsupported.unsupported_file_type"))
                Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
