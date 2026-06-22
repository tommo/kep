import SwiftUI
import UniformTypeIdentifiers
import MindoCore

/// Horizontal scrollable strip of tabs above the editor pane.
struct DocumentTabBar: View {
    @Binding var session: AppSession
    /// UUID of the tab currently being dragged, so the source can render
    /// faded while in-flight. Cleared on drop / drop-cancel.
    @State private var draggingID: OpenDocument.ID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(session.openDocuments) { doc in
                    HStack(spacing: 4) {
                        Image(systemName: tabIcon(for: doc))
                        Text(doc.title)
                            .lineLimit(1)
                        if doc.hasExternalChanges {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                                .help(L("tab.tooltip.modified_externally"))
                        } else if doc.isDirty {
                            // Unsaved-edits dot — distinct color from the
                            // orange external-changes marker so the user can
                            // tell at a glance which side made the change.
                            Circle()
                                .fill(Color.secondary)
                                .frame(width: 6, height: 6)
                                .help(L("tab.tooltip.unsaved_changes"))
                        }
                        Button {
                            // Route through closeTab so the FileWatcher is
                            // torn down and the MRU tab tracker stays
                            // consistent — the old inline removal leaked
                            // watchers and corrupted ⌃⇥ navigation.
                            session.closeTab(doc.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(doc.id == session.activeDocumentID ? Color.accentColor.opacity(0.18) : Color.clear)
                    )
                    // The strip lives in the title-bar band, so AppKit would treat
                    // a press-drag on a tab as a window move and swallow the
                    // reorder drag. Mark the tab cell non-window-draggable.
                    .background(WindowDragGuard())
                    .opacity(draggingID == doc.id ? 0.4 : 1.0)
                    .onTapGesture {
                        // Clicking a tab is a deliberate switch — focus that
                        // document's editor (one-shot), don't leave focus stranded
                        // on the sidebar from a prior browse.
                        session.pendingEditorFocus = true
                        session.activeDocumentID = doc.id
                        session.persistOpenTabs()
                    }
                    .onDrag {
                        draggingID = doc.id
                        return NSItemProvider(object: doc.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: TabDropDelegate(
                            target: doc.id,
                            session: $session,
                            draggingID: $draggingID
                        )
                    )
                    .contextMenu {
                        Button(L("tab.menu.close")) { session.closeTab(doc.id) }
                        Button(L("tab.menu.close_others")) { session.closeOtherTabs(keep: doc.id) }
                            .disabled(session.openDocuments.count < 2)
                        Button(L("tab.menu.close_all")) { session.closeAllTabs() }
                        Divider()
                        Button(L("tab.menu.reload")) { session.reloadTab(doc.id) }
                            .disabled(!doc.hasExternalChanges)
                        Button(L("tab.menu.reveal_in_finder")) {
                            if let url = doc.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                        .disabled(doc.fileURL == nil)
                    }
                }
                // "New document view" button (Obsidian's +). Each entry opens a
                // fresh UNTITLED doc in its OWN tab held in memory — it does NOT
                // write a file into the workspace (that's File ▸ New / the sidebar
                // context menu). Save (⌘S) chooses the path later.
                Menu {
                    Button(L("menu.file.new_mindmap")) { session.newDocViewTab(.mindMap) }
                    Button(L("menu.file.new_markdown")) { session.newDocViewTab(.markdown) }
                    Button(L("menu.file.new_csv")) { session.newDocViewTab(.csv) }
                    Button(L("menu.file.new_plantuml")) { session.newDocViewTab(.plantUML) }
                    Button(L("menu.file.new_notebook")) { session.newDocViewTab(.mindNotebook) }
                    Button(L("menu.file.new_text")) { session.newDocViewTab(.plainText) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("tab.new_document"))
            }
            .padding(.horizontal, 8)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                // Drop a file from Finder onto the strip → open as new tab.
                // Per-tab .onDrop above handles intra-strip reorder via .text;
                // file URLs go straight here.
                var anyHandled = false
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async { session.open(url: url) }
                    }
                    anyHandled = true
                }
                return anyHandled
            }
        }
    }

    private func tabIcon(for doc: OpenDocument) -> String {
        switch doc.kind {
        case .mindMap:
            return SupportedFileType.mindMap.sfSymbolName
        case .text(_, let t):
            return (t ?? .plainText).sfSymbolName
        case .unsupported:
            return SupportedFileType.unknownSymbolName
        }
    }
}

/// Per-tab drop target. Reads the source's UUID from the item provider,
/// then reorders `openDocuments` via the pure `TabReorder.move` helper so
/// the math matches what the unit tests cover. Persists on commit.
private struct TabDropDelegate: DropDelegate {
    let target: OpenDocument.ID
    @Binding var session: AppSession
    @Binding var draggingID: OpenDocument.ID?

    func dropEntered(info: DropInfo) {
        // Live-reorder while hovering — UUIDs of the open docs reorder so
        // the drop indicator visibly tracks the cursor between tabs.
        guard let source = draggingID, source != target else { return }
        let ids = session.openDocuments.map(\.id)
        let reordered = TabReorder.move(ids, from: source, to: target)
        guard reordered != ids else { return }
        let mapped = reordered.compactMap { id in session.openDocuments.first(where: { $0.id == id }) }
        session.openDocuments = mapped
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        session.persistOpenTabs()
        return true
    }

    func dropExited(info: DropInfo) {}
}

/// A zero-cost AppKit backing view that opts its region OUT of window dragging.
/// The tab strip sits in the transparent title-bar band (the strip is pulled
/// flush to the window top), where AppKit otherwise interprets a press-drag as
/// "move the window" and never lets SwiftUI's `.onDrag` reorder begin. Using it
/// as a tab's `.background` makes the tab the hit view with
/// `mouseDownCanMoveWindow == false`, so the drag reorders instead. Empty strip
/// gaps keep the default behaviour, so the window is still draggable there.
struct WindowDragGuard: NSViewRepresentable {
    final class GuardView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
    func makeNSView(context: Context) -> NSView { GuardView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
