import SwiftUI
import MindoMindMap

/// Right-hand area: tab strip on top, active editor below.
struct DetailArea: View {
    @Binding var session: AppSession
    /// Drives `.system` theme resolution: reading colorScheme makes this view
    /// re-render (and re-resolve the canvas theme) when the appearance flips.
    @Environment(\.colorScheme) private var colorScheme

    /// The active canvas theme, recomputed when the custom canvas colors change
    /// (reads `canvasThemeRevision` so Observation re-renders on a custom edit
    /// even though the ThemeChoice itself is unchanged) and when the system
    /// appearance flips (via colorScheme) for the `.system` choice.
    private var resolvedCanvasTheme: MindMapTheme {
        _ = session.canvasThemeRevision
        // A per-document theme override (stored in the map) wins over the global.
        let choice = session.activeMapThemeChoice ?? session.theme
        return choice.resolved(dark: colorScheme == .dark)
    }

    var body: some View {
        GeometryReader { geo in
            // The collapsed sidebar lets the detail reach the window's left edge,
            // where NavigationSplitView floats its OWN sidebar-toggle (an NSToolbar
            // item that re-adds itself, so it can't be removed) — it IS the reveal
            // control. Measured in-window: traffic lights end ~79pt, the toggle
            // item spans x≈100–148, so the tabs must clear window-x 150.
            //
            // Derive the gutter from the column's LIVE left edge instead of the
            // sidebarVisible bool: gutter = 150 − leftEdge. When the column
            // snaps/slides, its minX changes and the gutter recomputes in the SAME
            // layout pass, so the tabs are glued to wherever the column actually is
            // — no independent gutter animation racing the column (the old bool
            // version made the tabs lurch the opposite way, then back).
            let leftEdge = geo.frame(in: .global).minX
            let gutter = max(0, 150 - leftEdge)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: gutter)
                    DocumentTabBar(session: $session)
                    Divider()
                    Button {
                        session.outlineOpen.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                            .foregroundStyle(session.outlineOpen ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(session.outlineOpen ? L("menu.window.hide_outline") : L("menu.window.show_outline"))
                    .padding(.horizontal, 8)
                }
                // Match the macOS unified-toolbar height (52pt) so the tabs
                // vertically center on the SAME line as the traffic lights and the
                // system sidebar toggle, which the window centers in that 52pt band
                // (measured toggle center = 26pt from the window top).
                .frame(height: 52)
                // The tab strip's bottom border doubles as the document focus hint:
                // an accent line when the doc region holds focus (the old top accent
                // bar sat under the hidden title bar / window edge, unreadable).
                Rectangle()
                    .fill(session.activeRegion == .document ? Color.accentColor : Color(nsColor: .separatorColor))
                    .frame(height: 2)   // constant height — only the COLOR changes, so focus never shifts layout
                if let doc = session.activeDocument {
                    EditorPane(session: $session, documentID: doc.id, theme: resolvedCanvasTheme)
                        .id(doc.id)
                } else {
                    ContentUnavailableView(
                        L("detail.empty.title"),
                        systemImage: "doc",
                        description: Text(L("detail.empty.description"))
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The gutter follows live geometry; never let it animate on its own.
            .animation(nil, value: gutter)
        }
    }
}
