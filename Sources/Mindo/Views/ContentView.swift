import SwiftUI
import MindoBase
import MindoCore

/// Top-level window content: split view (sidebar | detail with outline
/// inspector), plus the global error alert. Owned by `MindoApp.body`.
struct ContentView: View {
    @Binding var session: AppSession
    @State private var sidebarSelection: NodeData?
    /// What drove the pending selection change. Arrow keys set this to
    /// `.keyboardNavigation` just before the List moves the highlight, so the
    /// open-on-selection rule below can skip them; reset to `.pointer` after
    /// each change so the next click opens as usual.
    @State private var selectionSource: SidebarSelectionSource = .pointer

    /// Maps the persisted `sidebarVisible` bool to the split view's
    /// column-visibility, and writes back when the user collapses the
    /// column by dragging so the menu state + persistence stay in sync.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { session.sidebarVisible ? .all : .detailOnly },
            set: { session.sidebarVisible = ($0 != .detailOnly) }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            SidebarView(
                session: $session,
                selection: $sidebarSelection,
                onSelectionSource: { selectionSource = $0 },
                onConfirm: openSelectedFile
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 280)
        } detail: {
            DetailArea(session: $session)
                .inspector(isPresented: $session.outlineOpen) {
                    OutlinePanel(items: session.outlineItems) { item in
                        session.requestOutlineNavigation(target: item.target)
                    }
                    .navigationTitle(L("detail.outline.title"))
                    .inspectorColumnWidth(min: 220, ideal: 260, max: 380)
                }
        }
        .onChange(of: sidebarSelection) { _, new in
            // Open on selection (single-click, Obsidian-style) but only when
            // the rule says so — skips folders, the already-active file (so
            // the reverse active-doc→selection sync can't loop back into a
            // redundant re-open), and arrow-key traversal (which only moves
            // the highlight; Return opens). See SidebarOpenDecision.
            if SidebarOpenDecision.shouldOpen(
                isFile: new?.isFile ?? false,
                selectedURL: new?.url,
                activeURL: session.activeDocument?.fileURL,
                source: selectionSource
            ), let node = new {
                session.open(url: node.url)
            }
            // Next change is a click again unless an arrow key re-flags it.
            selectionSource = .pointer
        }
        // Reverse direction: when the active doc changes (tab click, ⌃⇥
        // cycle, etc.), reflect that selection in the sidebar so the user
        // can see where the doc lives. Skipped when sidebarSelection is
        // already correct to avoid the open→select→open feedback loop.
        .onChange(of: session.activeDocumentID) { _, _ in
            guard let url = session.activeDocument?.fileURL,
                  let node = sidebarNode(for: url),
                  sidebarSelection?.url != node.url else { return }
            sidebarSelection = node
        }
        .alert(L("error.alert_title"), isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("OK") { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }

    /// Open the currently-highlighted sidebar file (Return key, R6). Honours
    /// the same file/folder/active-doc guards as click-to-open.
    private func openSelectedFile() {
        guard let node = sidebarSelection,
              SidebarOpenDecision.shouldOpen(
                isFile: node.isFile,
                selectedURL: node.url,
                activeURL: session.activeDocument?.fileURL,
                source: .keyboardConfirm
              ) else { return }
        session.open(url: node.url)
    }

    /// Walk every workspace tree looking for the node whose URL matches.
    /// Used for sidebar reveal-on-tab. Loaded children only — files
    /// inside collapsed folders won't be found, but that's the right
    /// trade-off (auto-expanding folders to reveal a tab would be loud).
    private func sidebarNode(for url: URL) -> NodeData? {
        for root in session.workspaceRoots {
            if let hit = findNode(in: root, matching: url) { return hit }
        }
        return nil
    }

    private func findNode(in node: NodeData, matching url: URL) -> NodeData? {
        if node.url.standardizedFileURL == url.standardizedFileURL { return node }
        guard node.isExpandable else { return nil }
        for child in node.children() {
            if let hit = findNode(in: child, matching: url) { return hit }
        }
        return nil
    }
}

