import SwiftUI
import MindoMarkdown

/// Roomy, resizable editor for a node's note — opened from the inspector's
/// expand button when the cramped inspector strip isn't enough. Edits the same
/// binding live, so changes land on the node as you type; Done just dismisses.
struct NoteEditorSheet: View {
    let text: Binding<String>
    let isDarkMode: Bool
    let title: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title.map { String(format: L("inspector.note.title_fmt"), $0) }
                     ?? L("inspector.note"))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(L("common.done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            MarkdownEditor(text: text, isDarkMode: isDarkMode)
        }
        .frame(minWidth: 520, idealWidth: 680, minHeight: 380, idealHeight: 520)
    }
}
