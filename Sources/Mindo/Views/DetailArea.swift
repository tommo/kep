import SwiftUI

/// Right-hand area: tab strip on top, active editor below.
struct DetailArea: View {
    @Binding var session: AppSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
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
            .frame(height: 32)
            Divider()
            if let doc = session.activeDocument {
                EditorPane(session: $session, documentID: doc.id, theme: session.theme.theme)
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
