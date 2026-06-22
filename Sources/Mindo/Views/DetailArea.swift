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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Collapsed sidebar → the detail reaches the window's left edge,
                // and NavigationSplitView floats its OWN sidebar-toggle there
                // (an NSToolbar item that re-adds itself, so it can't be removed).
                // It IS the reveal control. Measured in-window: traffic lights end
                // ~79pt, the toggle item spans x≈100–148. Offset the tabs to 150pt
                // so they clear it — no duplicate button, no overlap.
                if !session.sidebarVisible {
                    Color.clear.frame(width: 150)
                }
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
            // Match the macOS unified-toolbar height (52pt) so the tabs vertically
            // center on the SAME line as the traffic lights and the system sidebar
            // toggle, which the window centers in that 52pt band (measured toggle
            // center = 26pt from the window top). A shorter strip floats the tabs
            // above the system controls — the misalignment in the screenshots.
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
    }
}
