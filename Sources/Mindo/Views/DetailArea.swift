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
        return session.theme.resolved(dark: colorScheme == .dark)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                DocumentTabBar(session: $session)
                Divider()
                // "New document" dropdown in the doc-zone header. A plain menu
                // (click opens the list) — no surprise primary action.
                Menu {
                    Button(L("menu.file.new_mindmap"))  { session.newMindMap() }
                    Button(L("menu.file.new_markdown")) { session.newMarkdown() }
                    Button(L("menu.file.new_plantuml")) { session.newPlantUML() }
                    Button(L("menu.file.new_csv"))      { session.newCSV() }
                    Button(L("menu.file.new_notebook")) { session.newResearchNotebook() }
                    Button(L("menu.file.new_text"))     { session.newTextFile() }
                } label: {
                    Label(L("detail.new_document"), systemImage: "doc.badge.plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L("detail.new_document"))
                .padding(.horizontal, 8)
                Button {
                    session.outlineOpen.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .foregroundStyle(session.outlineOpen ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(session.outlineOpen ? L("menu.window.hide_outline") : L("menu.window.show_outline"))
                .padding(.trailing, 8)
            }
            .frame(height: 32)
            Divider()
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
