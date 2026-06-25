import SwiftUI
import AppKit
import KepBase

/// The dedicated CSV block editing/evaluation area. It docks below the spreadsheet
/// grid and edits the one block currently selected in the inspector list
/// (`model.selectedBlockID`): a roomy Lua source editor, run/eval controls, and
/// the full result (printed output + returned value, or the error). When no
/// block is selected it collapses to nothing, leaving the grid full-height.
///
/// Height is user-adjustable via the drag handle along its top edge.
public struct CSVBlockEditor: View {
    @ObservedObject var model: CSVBlocksModel
    let isDark: Bool

    @State private var height: CGFloat = 240
    @State private var dragStartHeight: CGFloat?

    public init(model: CSVBlocksModel, isDark: Bool) {
        self.model = model
        self.isDark = isDark
    }

    public var body: some View {
        if let idx = model.blocks.firstIndex(where: { $0.id == model.selectedBlockID }) {
            VStack(spacing: 0) {
                resizeHandle
                editor(for: $model.blocks[idx])
                    .frame(height: height)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// Drag the top edge to resize the editor area (clamped 120…560).
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .overlay {
                Color.clear
                    .frame(height: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStartHeight ?? height
                                if dragStartHeight == nil { dragStartHeight = start }
                                height = min(560, max(120, start - value.translation.height))
                            }
                            .onEnded { _ in dragStartHeight = nil }
                    )
            }
    }

    @ViewBuilder private func editor(for block: Binding<CSVEvalBlock>) -> some View {
        let id = block.wrappedValue.id
        let result = model.results[id]
        VStack(spacing: 0) {
            // Toolbar: name field + run / delete / close.
            HStack(spacing: 6) {
                Image(systemName: "function").foregroundStyle(.secondary)
                TextField("name", text: block.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 240)
                    .onSubmit { model.runAll() }
                    .onChange(of: block.wrappedValue.name) { _, _ in model.edited() }
                Spacer()
                Button { model.run(id) } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .help("Run (⌘↩)")
                Button { model.deleteBlock(id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete block")
                Button { model.selectedBlockID = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Close editor")
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()

            // Source editor + result, side by side so you can see both while editing.
            HSplitView {
                LuaCodeEditor(text: block.source, isDark: isDark)
                    .frame(minWidth: 220)
                    .onChange(of: block.wrappedValue.source) { _, _ in model.edited() }
                resultPane(result)
                    .frame(minWidth: 160, idealWidth: 220)
            }
        }
    }

    @ViewBuilder private func resultPane(_ result: CSVBlockResult?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Result").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let result, result.error == nil {
                    Button { copy(result) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy result").font(.caption2)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let result {
                        if let err = result.error {
                            Text(err)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.red).textSelection(.enabled)
                        } else {
                            if !result.output.trimmingCharacters(in: .newlines).isEmpty {
                                Text(result.output.trimmingCharacters(in: .newlines))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Text("= \(result.value)")
                                .font(.system(.callout, design: .monospaced).weight(.semibold))
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("Not run yet — ⌘↩ or Run.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    /// Copy a block's result — printed output (if any) followed by the value.
    private func copy(_ result: CSVBlockResult) {
        let out = result.output.trimmingCharacters(in: .newlines)
        let text = out.isEmpty ? result.value : out + "\n" + result.value
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
