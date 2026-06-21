import SwiftUI
import MindoBase

/// Observable state for an open notebook: the ordered cells, cached outputs,
/// and which cells are mid-run. Edits mutate cells in place (stable ids), then
/// debounce-serialize back to the document text. Lives in MindoMarkdown (pure);
/// execution is injected by the app.
@MainActor
final class NotebookModel: ObservableObject {
    @Published var cells: [NotebookCell]
    @Published var outputs: ExecOutputs
    @Published var running: Set<String> = []

    let documentURL: URL?
    let runOne: NotebookRunOne
    let runAll: NotebookRunAll
    private let onSerialize: (String) -> Void
    private var lastSerialized: String
    private let debouncer = Debouncer()
    private var uid = 0

    init(text: String, documentURL: URL?,
         runOne: @escaping NotebookRunOne, runAll: @escaping NotebookRunAll,
         onSerialize: @escaping (String) -> Void) {
        self.documentURL = documentURL
        self.runOne = runOne
        self.runAll = runAll
        self.onSerialize = onSerialize
        self.cells = NotebookFormat.parse(text).cells
        self.lastSerialized = text
        self.outputs = documentURL.map { ExecOutputsStore.load(for: $0) } ?? ExecOutputs()
    }

    private var ctx: NotebookRunContext { NotebookRunContext(documentURL: documentURL) }

    /// Re-parse when the document changed underneath us (external edit / reload),
    /// not from our own serialize echo.
    func reload(from text: String) {
        guard text != lastSerialized else { return }
        cells = NotebookFormat.parse(text).cells
        lastSerialized = text
        outputs = documentURL.map { ExecOutputsStore.load(for: $0) } ?? ExecOutputs()
    }

    private func freshID(_ prefix: String) -> String { uid += 1; return "u\(prefix)-\(uid)" }

    private func index(of id: String) -> Int? { cells.firstIndex { $0.id == id } }

    func text(of id: String) -> String {
        switch cells.first(where: { $0.id == id }) {
        case .prose(_, let t): return t
        case .code(_, _, let c): return c
        case .none: return ""
        }
    }

    func updateText(_ id: String, _ newText: String) {
        guard let i = index(of: id) else { return }
        switch cells[i] {
        case .prose(let cid, _): cells[i] = .prose(id: cid, text: newText)
        case .code(let cid, let lang, _): cells[i] = .code(id: cid, language: lang, code: newText)
        }
        scheduleSerialize()
    }

    func addCode(after id: String? = nil) {
        let cell = NotebookCell.code(id: freshID("code"), language: "lua", code: "")
        insert(cell, after: id)
    }
    func addProse(after id: String? = nil) {
        let cell = NotebookCell.prose(id: freshID("prose"), text: "")
        insert(cell, after: id)
    }
    private func insert(_ cell: NotebookCell, after id: String?) {
        if let id, let i = index(of: id) { cells.insert(cell, at: i + 1) } else { cells.append(cell) }
        scheduleSerialize()
    }
    func delete(_ id: String) {
        cells.removeAll { $0.id == id }
        scheduleSerialize()
    }
    func move(_ id: String, by offset: Int) {
        guard let i = index(of: id) else { return }
        let j = i + offset
        guard j >= 0, j < cells.count else { return }
        cells.swapAt(i, j)
        scheduleSerialize()
    }

    private func scheduleSerialize() {
        debouncer.schedule(after: 0.4) { [weak self] in
            Task { @MainActor in self?.flush() }
        }
    }
    private func flush() {
        let s = NotebookFormat.serialize(Notebook(cells: cells))
        lastSerialized = s
        onSerialize(s)
    }

    // MARK: - Execution

    func output(for id: String) -> ExecOutput? {
        guard case .code(_, _, let code)? = cells.first(where: { $0.id == id }) else { return nil }
        return outputs.output(forHash: MarkdownExecBlocks.hash(code))
    }
    func isStale(_ id: String) -> Bool {
        guard case .code(_, _, let code)? = cells.first(where: { $0.id == id }) else { return false }
        return outputs.output(forHash: MarkdownExecBlocks.hash(code)) == nil
    }

    func run(_ id: String) async {
        guard case .code(_, _, let code)? = cells.first(where: { $0.id == id }) else { return }
        running.insert(id)
        let out = await runOne(code, ctx)
        outputs.set(out, forHash: MarkdownExecBlocks.hash(code))
        running.remove(id)
    }

    func runAllCells() async {
        let nb = Notebook(cells: cells)
        let ids = nb.codeCells.map(\.id)
        running.formUnion(ids)
        outputs = await runAll(nb, ctx)
        running.subtract(ids)
    }

    func clearOutputs() {
        outputs = ExecOutputs()
        if let url = documentURL { try? ExecOutputsStore.save(outputs, for: url) }
    }
}

/// The cell-based Research Notebook editor: a vertical list of prose + code
/// cells with per-cell run + a Run-All toolbar. Outputs render beneath code
/// cells; a "stale" badge shows when a cell changed since its last run.
public struct NotebookEditor: View {
    @Binding var text: String
    let documentURL: URL?
    let isDarkMode: Bool
    @StateObject private var model: NotebookModel

    public init(text: Binding<String>, documentURL: URL?, isDarkMode: Bool,
                runOne: @escaping NotebookRunOne, runAll: @escaping NotebookRunAll) {
        _text = text
        self.documentURL = documentURL
        self.isDarkMode = isDarkMode
        _model = StateObject(wrappedValue: NotebookModel(
            text: text.wrappedValue, documentURL: documentURL,
            runOne: runOne, runAll: runAll,
            onSerialize: { text.wrappedValue = $0 }))
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.cells) { cell in
                        NotebookCellRow(model: model, cell: cell)
                    }
                    addBar
                }
                .padding(12)
            }
        }
        .onChange(of: text) { _, new in model.reload(from: new) }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { Task { await model.runAllCells() } } label: {
                Label("Run All", systemImage: "play.fill")
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(!model.running.isEmpty)
            .help("Run all cells (⇧⌘↩)")
            Button { model.clearOutputs() } label: {
                Label("Clear Outputs", systemImage: "eraser")
            }
            Spacer()
            Text("⌘↩ run cell · ⇧⌘↩ run all").font(.caption2).foregroundStyle(.tertiary)
            if !model.running.isEmpty { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            Button { model.addProse() } label: { Label("Text", systemImage: "text.alignleft") }
            Button { model.addCode() } label: { Label("Code", systemImage: "chevron.left.forwardslash.chevron.right") }
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.top, 4)
    }
}

private struct NotebookCellRow: View {
    @ObservedObject var model: NotebookModel
    let cell: NotebookCell
    @State private var editingProse = false
    @FocusState private var proseFocused: Bool

    private var binding: Binding<String> {
        Binding(get: { model.text(of: cell.id) }, set: { model.updateText(cell.id, $0) })
    }

    /// Grow the code editor with its content (no nested scroll); clamp so a huge
    /// cell doesn't dominate the notebook.
    private func codeHeight(_ code: String) -> CGFloat {
        let lines = max(3, code.components(separatedBy: "\n").count)
        return CGFloat(min(lines, 30)) * 18 + 16
    }

    var body: some View {
        switch cell {
        case .prose:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "text.alignleft").foregroundStyle(.secondary).font(.caption).padding(.top, 6)
                if editingProse {
                    TextEditor(text: binding)
                        .font(.body)
                        .frame(minHeight: 40)
                        .scrollContentBackground(.hidden)
                        .focused($proseFocused)
                        .onAppear { proseFocused = true }
                        .onChange(of: proseFocused) { _, focused in if !focused { editingProse = false } }
                } else {
                    ProseRenderedView(markdown: model.text(of: cell.id))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { editingProse = true }
                }
                cellMenu
            }
        case .code:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(.secondary).font(.caption)
                    Text("lua").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    if model.running.contains(cell.id) {
                        ProgressView().controlSize(.small)
                    } else {
                        Button { Task { await model.run(cell.id) } } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Run cell")
                    }
                    cellMenu
                }
                NotebookCodeView(text: binding) { Task { await model.run(cell.id) } }
                    .frame(height: codeHeight(binding.wrappedValue))
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.10)))
                outputView
            }
        }
    }

    @ViewBuilder private var outputView: some View {
        if let out = model.output(for: cell.id) {
            VStack(alignment: .leading, spacing: 2) {
                if model.isStale(cell.id) {
                    Text("stale — re-run").font(.caption2).foregroundStyle(.orange)
                }
                Text(out.error ?? out.text)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(out.error != nil ? Color.red : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
        }
    }

    private var cellMenu: some View {
        Menu {
            Button("Move Up") { model.move(cell.id, by: -1) }
            Button("Move Down") { model.move(cell.id, by: 1) }
            Divider()
            Button("Delete Cell", role: .destructive) { model.delete(cell.id) }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// Monospaced Lua source editor for a code cell that runs the cell from the
/// keyboard — ⌘↩ or ⇧↩ (Jupyter-style), so notebooks aren't mouse-only.
/// Backed by an NSTextView (SwiftUI TextEditor can't intercept those keys).
struct NotebookCodeView: NSViewRepresentable {
    @Binding var text: String
    var onRun: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = CodeArea.makeMonospaced(text: text, delegate: context.coordinator) {
            NotebookCodeTextView()
        }
        scroll.hasVerticalScroller = false   // outer notebook ScrollView scrolls
        (tv as? NotebookCodeTextView)?.onRun = onRun
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        (tv as? NotebookCodeTextView)?.onRun = onRun
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        weak var textView: NSTextView?
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, tv.string != text.wrappedValue else { return }
            text.wrappedValue = tv.string
        }
    }
}

/// NSTextView that runs its cell on ⌘↩ / ⇧↩ and otherwise behaves normally
/// (plain Return inserts a newline).
final class NotebookCodeTextView: NSTextView {
    var onRun: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {   // Return
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if mods == .command || mods == .shift { onRun?(); return }
        }
        super.keyDown(with: event)
    }
}

/// Read view for a prose cell: renders markdown line-by-line (headings, bullets,
/// inline emphasis) without a WKWebView. Click to switch to editing.
private struct ProseRenderedView: View {
    let markdown: String

    var body: some View {
        let lines = ProseMarkdown.lines(markdown)
        if lines.allSatisfy({ $0 == .blank }) {
            Text("Empty — click to write…").foregroundStyle(.tertiary).italic()
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    lineView(line)
                }
            }
        }
    }

    @ViewBuilder private func lineView(_ line: ProseLine) -> some View {
        switch line {
        case .blank:
            Spacer().frame(height: 4)
        case .heading(let level, let text):
            inline(text).font(headingFont(level)).bold()
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(text)
            }
        case .text(let text):
            inline(text)
        }
    }

    /// Inline markdown (bold/italic/code/links) via AttributedString; falls back
    /// to plain text if it can't parse.
    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(markdown: s) { return Text(attr) }
        return Text(s)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }
}
