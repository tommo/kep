import SwiftUI
import KepCore

/// Modal sheet for browsing snippets and choosing one to insert. Caller passes
/// the active document's file type to seed the filter and a closure that
/// performs the insertion.
@MainActor
public struct SnippetPicker: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SnippetStore()
    @State private var query: String = ""
    @State private var selectionID: Snippet.ID?
    @State private var preview: String = ""

    public let fileType: SupportedFileType?
    public let onInsert: (Snippet) -> Void

    public init(fileType: SupportedFileType?, onInsert: @escaping (Snippet) -> Void) {
        self.fileType = fileType
        self.onInsert = onInsert
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Snippets").font(.title3).bold()
                if let ft = fileType {
                    Text(".\(ft.rawValue)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.15)))
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            Divider()

            HStack(spacing: 0) {
                listColumn
                    .frame(minWidth: 240, idealWidth: 280)
                Divider()
                previewColumn
                    .frame(minWidth: 280)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Insert") {
                    if let id = selectionID, let snippet = store.all.first(where: { $0.id == id }) {
                        onInsert(snippet)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectionID == nil)
            }
            .padding()
        }
        .frame(width: 720, height: 480)
        .onChange(of: selectionID) { _, _ in updatePreview() }
        .onAppear { selectionID = filtered.first?.id; updatePreview() }
    }

    private var filtered: [Snippet] {
        store.filter(fileType: fileType, query: query)
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            TextField("Filter snippets…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List(filtered, selection: $selectionID) { snippet in
                HStack(spacing: 6) {
                    if snippet.isBuiltIn {
                        Image(systemName: "shippingbox").foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "person.crop.circle").foregroundStyle(.tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.title).lineLimit(1)
                        if !snippet.tags.isEmpty {
                            Text(snippet.tags.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tag(snippet.id)
            }
            .listStyle(.sidebar)
        }
    }

    private var previewColumn: some View {
        ScrollView {
            Text(preview.isEmpty ? "Select a snippet to preview" : preview)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))
        .padding(8)
    }

    private func updatePreview() {
        if let id = selectionID, let snippet = store.all.first(where: { $0.id == id }) {
            preview = snippet.body
        } else {
            preview = ""
        }
    }
}
