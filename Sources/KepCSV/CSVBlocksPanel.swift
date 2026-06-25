import SwiftUI
import AppKit
import KepBase

/// The CSV "sheet blocks" inspector list (right pane of the CSV editor): a
/// compact overview of the user-composed Lua computations over the table. Each
/// row shows only the essentials — name, a run button, and the last result.
/// Selecting a row opens that block in the dedicated editor area below the grid
/// (`CSVBlockEditor`); editing the Lua source lives there, not here.
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
                    VStack(spacing: 1) {
                        ForEach(model.blocks) { block in
                            blockRow(block)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 200)
    }

    @ViewBuilder private func blockRow(_ block: CSVEvalBlock) -> some View {
        let result = model.results[block.id]
        let selected = model.selectedBlockID == block.id
        Button {
            model.selectedBlockID = block.id
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.name.isEmpty ? "(unnamed)" : block.name)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .lineLimit(1)
                    resultLine(result)
                }
                Spacer(minLength: 4)
                Button { model.run(block.id) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless).help("Run (⌘↩)")
                    .font(.caption)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    /// The single-line result preview shown under a block's name in the list.
    /// On failure we show only a quiet badge — the full (readable) error lives
    /// in the editor's result pane; dumping it in this narrow row is just noise.
    @ViewBuilder private func resultLine(_ result: CSVBlockResult?) -> some View {
        if let result {
            if result.error != nil {
                Label("error", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2).foregroundStyle(.red)
            } else {
                Text("= \(result.value)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        } else {
            Text("not run")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
