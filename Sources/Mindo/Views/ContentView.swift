import SwiftUI
import MindoBase
import MindoCore

/// Top-level window content: split view (sidebar | detail with outline
/// inspector), plus the global error alert. Owned by `MindoApp.body`.
struct ContentView: View {
    @Binding var session: AppSession
    @State private var sidebarSelection: NodeData?

    var body: some View {
        NavigationSplitView {
            SidebarView(session: $session, selection: $sidebarSelection)
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
            if let node = new, node.isFile {
                session.open(url: node.url)
            }
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
}
