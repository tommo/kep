import SwiftUI

/// The CSV "sheet blocks" panel (right pane of the CSV editor): user-composed
/// Lua computations over the table. Each block has a name (referenceable from
/// cells as `=name`), a Lua source, and its last result/output inline.
public struct CSVBlocksPanel: View {
    @ObservedObject var model: CSVBlocksModel

    public init(model: CSVBlocksModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Blocks").font(.headline)
                Spacer()
                Button { model.runAll() } label: { Image(systemName: "play.fill") }
                    .help("Run all blocks (⌘↩)").buttonStyle(.borderless)
                Button { model.addBlock() } label: { Image(systemName: "plus") }
                    .help("Add a block").buttonStyle(.borderless)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()

            if model.blocks.isEmpty {
                Text("No blocks — + to add")
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach($model.blocks) { $block in
                            blockRow($block)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(minWidth: 220)
    }

    @ViewBuilder private func blockRow(_ block: Binding<CSVEvalBlock>) -> some View {
        let id = block.wrappedValue.id
        let result = model.results[id]
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                TextField("name", text: block.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { model.runAll() }
                    .onChange(of: block.wrappedValue.name) { _, _ in model.edited() }
                Button { model.runAll() } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless).help("Run (⌘↩)")
                Button { model.deleteBlock(id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete block")
            }
            TextEditor(text: block.source)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 46, maxHeight: 140)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15)))
                .onChange(of: block.wrappedValue.source) { _, _ in model.edited() }

            if let result {
                if let err = result.error {
                    Text(err).font(.system(.caption, design: .monospaced)).foregroundStyle(.red)
                        .textSelection(.enabled)
                } else {
                    if !result.output.isEmpty {
                        Text(result.output.trimmingCharacters(in: .newlines))
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("= \(result.value)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
