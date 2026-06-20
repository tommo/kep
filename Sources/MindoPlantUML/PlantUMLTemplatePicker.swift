import SwiftUI

/// Modal sheet shown when creating a new PlantUML document: browse the built-in
/// diagram templates, preview the source, and create. Mirrors `SnippetPicker`.
/// The caller passes a closure that creates the document from the chosen
/// template's body.
@MainActor
public struct PlantUMLTemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectionID: PlantUMLTemplate.ID?

    public let onCreate: (PlantUMLTemplate) -> Void

    public init(onCreate: @escaping (PlantUMLTemplate) -> Void) {
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New PlantUML").font(.title3).bold()
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            Divider()

            HStack(spacing: 0) {
                listColumn
                    .frame(minWidth: 220, idealWidth: 240)
                Divider()
                previewColumn
                    .frame(minWidth: 300)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectionID == nil)
            }
            .padding()
        }
        .frame(width: 700, height: 460)
        .onAppear { if selectionID == nil { selectionID = PlantUMLTemplates.blank.id } }
    }

    private var selected: PlantUMLTemplate? {
        selectionID.flatMap { PlantUMLTemplates.template(id: $0) }
    }

    private var listColumn: some View {
        List(selection: $selectionID) {
            ForEach(PlantUMLTemplates.grouped, id: \.category) { group in
                SwiftUI.Section(group.category) {
                    ForEach(group.templates) { template in
                        Text(template.name).tag(template.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var previewColumn: some View {
        ScrollView {
            Text(selected?.body ?? "Select a template to preview")
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))
        .padding(8)
    }

    private func create() {
        guard let template = selected else { return }
        onCreate(template)
        dismiss()
    }
}
