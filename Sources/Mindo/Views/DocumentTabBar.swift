import SwiftUI

/// Horizontal scrollable strip of tabs above the editor pane.
struct DocumentTabBar: View {
    @Binding var session: AppSession

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
                        }
                        Button {
                            if let idx = session.openDocuments.firstIndex(where: { $0.id == doc.id }) {
                                session.openDocuments.remove(at: idx)
                                if session.activeDocumentID == doc.id {
                                    session.activeDocumentID = session.openDocuments.last?.id
                                }
                            }
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
                    .onTapGesture { session.activeDocumentID = doc.id }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func tabIcon(for doc: OpenDocument) -> String {
        switch doc.kind {
        case .mindMap: return "brain"
        case .text(_, .markdown): return "text.alignleft"
        case .text(_, .plantUML): return "rectangle.connected.to.line.below"
        case .text(_, .csv): return "tablecells"
        case .text: return "doc.text"
        case .unsupported: return "doc"
        }
    }
}
