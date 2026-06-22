import SwiftUI
import MindoBase

/// Observable state for an open notebook: the ordered cells, cached outputs,
/// and which cells are mid-run. Edits mutate cells in place (stable ids), then
/// debounce-serialize back to the document text. Lives in MindoMarkdown (pure);
/// execution is injected by the app.
@MainActor
final class NotebookModel: ObservableObject, NotebookAgentSink {
    @Published var cells: [NotebookCell]
    @Published var outputs: ExecOutputs
    @Published var running: Set<String> = []
    @Published var agentBusy = false
    /// Per-agent-block tool-call trace (ephemeral — process info, not persisted).
    @Published var agentTrace: [String: [String]] = [:]

    let documentURL: URL?
    let runOne: NotebookRunOne
    let runAll: NotebookRunAll
    let runAgent: NotebookAgentRunner?
    private let onSerialize: (String) -> Void
    private var lastSerialized: String
    private let debouncer = Debouncer()
    private var uid = 0

    init(text: String, documentURL: URL?,
         runOne: @escaping NotebookRunOne, runAll: @escaping NotebookRunAll,
         runAgent: NotebookAgentRunner? = nil,
         onSerialize: @escaping (String) -> Void) {
        self.documentURL = documentURL
        self.runOne = runOne
        self.runAll = runAll
        self.runAgent = runAgent
        self.onSerialize = onSerialize
        self.cells = NotebookFormat.parse(text).cells
        self.lastSerialized = text
        self.outputs = documentURL.map { ExecOutputsStore.load(for: $0) } ?? ExecOutputs()
    }

    // MARK: - Agent block (first-class, attributed, re-runnable)

    /// The agent cell currently being authored into (set during runAgentCell).
    private var activeAgentCell: String?

    /// Run the agent for an agent cell's prompt — it authors its findings into
    /// that block's result, streamed live. Re-running clears the prior result.
    func runAgentCell(_ id: String) async {
        guard let runAgent,
              case .agent(_, let prompt, _, _)? = cells.first(where: { $0.id == id }),
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        setAgentResult(id, "")
        setAgentSources(id, [])
        agentTrace[id] = []
        activeAgentCell = id
        running.insert(id); agentBusy = true
        await runAgent(prompt, self)
        running.remove(id); agentBusy = false
        activeAgentCell = nil
        flushNow()
    }

    private func setAgentResult(_ id: String, _ result: String) {
        guard let i = index(of: id), case .agent(let cid, let prompt, _, let sources) = cells[i] else { return }
        cells[i] = .agent(id: cid, prompt: prompt, result: result, sources: sources)
    }
    private func setAgentSources(_ id: String, _ sources: [String]) {
        guard let i = index(of: id), case .agent(let cid, let prompt, let result, _) = cells[i] else { return }
        cells[i] = .agent(id: cid, prompt: prompt, result: result, sources: sources)
    }

    /// NotebookAgentSink — the agent reports the sources it consulted.
    func agentSetSources(_ sources: [String]) {
        guard let id = activeAgentCell else { return }
        setAgentSources(id, sources)
        flushNow()
    }
    func agentLog(_ step: String) {
        guard let id = activeAgentCell else { return }
        agentTrace[id, default: []].append(step)
    }
    func agentSteps(of id: String) -> [String] { agentTrace[id] ?? [] }
    private func appendToAgentResult(_ id: String, _ markdown: String) {
        let existing = agentResult(of: id)
        setAgentResult(id, existing.isEmpty ? markdown : existing + "\n\n" + markdown)
        flushNow()
    }

    // NotebookAgentSink — authored content lands in the active agent block.
    func agentAddProse(_ text: String) {
        guard let id = activeAgentCell else {
            cells.append(.prose(id: freshID("prose"), text: text)); flushNow(); return
        }
        appendToAgentResult(id, text)
    }
    func agentAddCode(_ code: String, output: ExecOutput) {
        let rendered = "```lua\n\(code)\n```\n→ " + (output.error ?? (output.text.isEmpty ? "(no output)" : output.text))
        guard let id = activeAgentCell else {
            cells.append(.code(id: freshID("code"), language: "lua", code: code))
            outputs.set(output, forHash: MarkdownExecBlocks.hash(code)); flushNow(); return
        }
        appendToAgentResult(id, rendered)
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
        case .agent(_, let prompt, _, _): return prompt   // editable field is the prompt
        case .none: return ""
        }
    }

    /// The agent block's authored result (rendered read-only).
    func agentResult(of id: String) -> String {
        if case .agent(_, _, let r, _)? = cells.first(where: { $0.id == id }) { return r }
        return ""
    }
    /// The source documents the agent consulted for this block.
    func agentSources(of id: String) -> [String] {
        if case .agent(_, _, _, let s)? = cells.first(where: { $0.id == id }) { return s }
        return []
    }

    func updateText(_ id: String, _ newText: String) {
        guard let i = index(of: id) else { return }
        switch cells[i] {
        case .prose(let cid, _): cells[i] = .prose(id: cid, text: newText)
        case .code(let cid, let lang, _): cells[i] = .code(id: cid, language: lang, code: newText)
        case .agent(let cid, _, let result, let sources): cells[i] = .agent(id: cid, prompt: newText, result: result, sources: sources)
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
    func addAgent(after id: String? = nil) {
        let cell = NotebookCell.agent(id: freshID("agent"), prompt: "", result: "", sources: [])
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
    /// Serialize immediately (agent edits — don't wait for the debounce).
    private func flushNow() { flush() }

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

    // MARK: - Selection / command-mode navigation (keyboard-only use)

    @Published var selectedID: String?

    private var selIndex: Int? { selectedID.flatMap { sid in cells.firstIndex { $0.id == sid } } }

    func selectFirstIfNeeded() { if selectedID == nil || selIndex == nil { selectedID = cells.first?.id } }
    func selectNext() {
        guard let i = selIndex else { selectedID = cells.first?.id; return }
        if i + 1 < cells.count { selectedID = cells[i + 1].id }
    }
    func selectPrev() {
        guard let i = selIndex, i > 0 else { return }
        selectedID = cells[i - 1].id
    }

    /// Add a cell after the selection (or at the end) and select it.
    func addAfterSelection(_ make: (String?) -> Void) {
        let anchor = selectedID
        let beforeIDs = Set(cells.map(\.id))
        make(anchor)
        if let new = cells.first(where: { !beforeIDs.contains($0.id) }) { selectedID = new.id }
    }
    func deleteSelected() {
        guard let id = selectedID, let i = selIndex else { return }
        cells.removeAll { $0.id == id }
        selectedID = cells.indices.contains(i) ? cells[i].id : cells.last?.id
        scheduleSerialize()
    }
    func moveSelected(by offset: Int) {
        guard let id = selectedID else { return }
        move(id, by: offset)   // selection follows the id
    }
    /// Run the selected cell (code → run, agent → research). Prose: no-op.
    func runSelected() async {
        guard let id = selectedID else { return }
        switch cells.first(where: { $0.id == id }) {
        case .code: await run(id)
        case .agent: await runAgentCell(id)
        default: break
        }
    }
}

/// The cell-based Research Notebook editor: a vertical list of prose + code
/// cells with per-cell run + a Run-All toolbar. Outputs render beneath code
/// cells; a "stale" badge shows when a cell changed since its last run.
/// Keyboard focus target for the notebook: command mode (cell navigation) or
/// editing a specific cell.
enum NotebookFocus: Hashable {
    case command
    case edit(String)
}

public struct NotebookEditor: View {
    @Binding var text: String
    let documentURL: URL?
    let isDarkMode: Bool
    let onOpenSource: ((String) -> Void)?
    /// Whether the notebook may take keyboard focus when it appears. False for a
    /// browse-open (sidebar single-click) so focus stays in the sidebar.
    let shouldFocusOnAppear: () -> Bool
    @StateObject private var model: NotebookModel
    @FocusState private var focus: NotebookFocus?

    public init(text: Binding<String>, documentURL: URL?, isDarkMode: Bool,
                runOne: @escaping NotebookRunOne, runAll: @escaping NotebookRunAll,
                runAgent: NotebookAgentRunner? = nil,
                onOpenSource: ((String) -> Void)? = nil,
                shouldFocusOnAppear: @escaping () -> Bool = { true }) {
        _text = text
        self.documentURL = documentURL
        self.isDarkMode = isDarkMode
        self.onOpenSource = onOpenSource
        self.shouldFocusOnAppear = shouldFocusOnAppear
        _model = StateObject(wrappedValue: NotebookModel(
            text: text.wrappedValue, documentURL: documentURL,
            runOne: runOne, runAll: runAll, runAgent: runAgent,
            onSerialize: { text.wrappedValue = $0 }))
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.cells) { cell in
                            NotebookCellRow(model: model, cell: cell,
                                            focus: $focus, isSelected: model.selectedID == cell.id,
                                            onOpenSource: onOpenSource)
                                .id(cell.id)
                        }
                        addBar
                    }
                    .padding(12)
                }
                .onChange(of: model.selectedID) { _, id in
                    if let id { withAnimation(.easeInOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
        .focusable()
        .focused($focus, equals: .command)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { handleCommandKey($0) }
        .onAppear {
            model.selectFirstIfNeeded()           // visual selection only
            if shouldFocusOnAppear() { focus = .command }   // don't steal focus on a browse-open
        }
        .onChange(of: focus) { _, f in if case .edit(let id)? = f { model.selectedID = id } }
        .onChange(of: text) { _, new in model.reload(from: new) }
        .onReceive(NotificationCenter.default.publisher(for: .focusNotebookCommand)) { _ in
            model.selectFirstIfNeeded(); focus = .command
        }
    }

    /// Command-mode keys (fire only when the notebook container — not a cell
    /// editor — holds focus). Makes the notebook fully keyboard-operable.
    private func handleCommandKey(_ press: KeyPress) -> KeyPress.Result {
        let opt = press.modifiers.contains(.option)
        switch press.key {
        case .upArrow:   opt ? model.moveSelected(by: -1) : model.selectPrev(); return .handled
        case .downArrow: opt ? model.moveSelected(by: 1) : model.selectNext(); return .handled
        case .return:
            if press.modifiers.contains(.command) || press.modifiers.contains(.shift) {
                Task { await model.runSelected() }
            } else if let id = model.selectedID {
                focus = .edit(id)
            }
            return .handled
        case .deleteForward, .delete:
            model.deleteSelected(); return .handled
        default: break
        }
        switch press.characters {
        case "b": model.addAfterSelection { model.addCode(after: $0) }; editSelected(); return .handled
        case "m": model.addAfterSelection { model.addProse(after: $0) }; editSelected(); return .handled
        case "g" where model.runAgent != nil: model.addAfterSelection { model.addAgent(after: $0) }; editSelected(); return .handled
        case "r": Task { await model.runSelected() }; return .handled
        default: return .ignored
        }
    }

    /// Drop straight into editing the (just-added) selected cell.
    private func editSelected() {
        if let id = model.selectedID { focus = .edit(id) }
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
            Text("↑↓ select · ⏎ edit · ⎋ done · ⌘↩ run · b/m/g add · ⌥↑↓ move · ⌦ delete")
                .font(.caption2).foregroundStyle(.tertiary)
            if !model.running.isEmpty { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            Button { model.addProse() } label: { Label("Text", systemImage: "text.alignleft") }
            Button { model.addCode() } label: { Label("Code", systemImage: "chevron.left.forwardslash.chevron.right") }
            if model.runAgent != nil {
                Button { model.addAgent() } label: { Label("Agent", systemImage: "sparkles") }
            }
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
    var focus: FocusState<NotebookFocus?>.Binding
    let isSelected: Bool
    var onOpenSource: ((String) -> Void)?

    private var isEditing: Bool { focus.wrappedValue == .edit(cell.id) }

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
        cellContent
            .padding(8)
            // The current/active cell gets a clear accent border (+ faint tint).
            // An editing cell is brighter still, so you can tell select vs edit.
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(isEditing ? 0.10 : 0.05) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                isSelected ? Color.accentColor.opacity(isEditing ? 1.0 : 0.6) : .clear,
                lineWidth: isEditing ? 2 : 1.5))
            // Select on click without blocking the editors' own clicks.
            .simultaneousGesture(TapGesture().onEnded { model.selectedID = cell.id })
    }

    @ViewBuilder private var cellContent: some View {
        switch cell {
        case .prose:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "text.alignleft").foregroundStyle(.secondary).font(.caption).padding(.top, 6)
                if isEditing {
                    TextEditor(text: binding)
                        .font(.body)
                        .frame(minHeight: 40)
                        .scrollContentBackground(.hidden)
                        .focused(focus, equals: .edit(cell.id))
                        .onKeyPress(.escape) { focus.wrappedValue = .command; return .handled }
                } else {
                    ProseRenderedView(markdown: model.text(of: cell.id))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedID = cell.id; focus.wrappedValue = .edit(cell.id) }
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
                        .help("Run cell (⌘↩)")
                    }
                    cellMenu
                }
                NotebookCodeView(text: binding, isEditing: isEditing,
                                 onRun: { Task { await model.run(cell.id) } },
                                 onEscape: { focus.wrappedValue = .command })
                    .frame(height: codeHeight(binding.wrappedValue))
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.10)))
                outputView
            }
        case .agent:
            agentCell
        }
    }

    /// First-class agent block: an attributed, re-runnable research prompt whose
    /// authored result (prose + ran code) lives inside the block.
    private var agentCell: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                Text("Agent").font(.caption.weight(.semibold)).foregroundStyle(.purple)
                Spacer()
                if model.running.contains(cell.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await model.runAgentCell(cell.id) } } label: {
                        Image(systemName: model.agentResult(of: cell.id).isEmpty ? "play.fill" : "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(model.agentResult(of: cell.id).isEmpty ? "Run research" : "Re-run")
                }
                cellMenu
            }
            // Custom placeholder so an EMPTY agent cell reads as a faint hint,
            // not real content (a plain TextField placeholder looked authored).
            ZStack(alignment: .topLeading) {
                if model.text(of: cell.id).isEmpty {
                    Text("Research question for the agent…")
                        .font(.body).italic().foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                TextField("", text: binding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .lineLimit(1...4)
                    .focused(focus, equals: .edit(cell.id))
                    .onKeyPress(.escape) { focus.wrappedValue = .command; return .handled }
                    .onSubmit { Task { await model.runAgentCell(cell.id) } }
            }
            let steps = model.agentSteps(of: cell.id)
            if !steps.isEmpty {
                DisclosureGroup("Research steps (\(steps.count))") {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { _, s in
                            Text(s).font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.caption2)
            }
            let result = model.agentResult(of: cell.id)
            if !result.isEmpty {
                Divider()
                ProseRenderedView(markdown: result)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.running.contains(cell.id) {
                Text("Researching…").font(.caption).foregroundStyle(.secondary)
            }
            let sources = model.agentSources(of: cell.id)
            if !sources.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "book.closed").font(.caption2).foregroundStyle(.secondary)
                    Text("Sources:").font(.caption2).foregroundStyle(.secondary)
                    ForEach(sources, id: \.self) { src in
                        if let open = onOpenSource {
                            Button(src) { open(src) }
                                .buttonStyle(.link).font(.caption2)
                        } else {
                            Text(src).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.18)))
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
    var isEditing: Bool = false
    var onRun: () -> Void
    var onEscape: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = CodeArea.makeMonospaced(text: text, delegate: context.coordinator) {
            NotebookCodeTextView()
        }
        scroll.hasVerticalScroller = false   // outer notebook ScrollView scrolls
        (tv as? NotebookCodeTextView)?.onRun = onRun
        (tv as? NotebookCodeTextView)?.onEscape = onEscape
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        (tv as? NotebookCodeTextView)?.onRun = onRun
        (tv as? NotebookCodeTextView)?.onEscape = onEscape
        // Bridge SwiftUI command-mode "edit" → make this the first responder.
        if isEditing, tv.window != nil, tv.window?.firstResponder !== tv {
            tv.window?.makeFirstResponder(tv)
        }
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
    var onEscape: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {   // Return
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if mods == .command || mods == .shift { onRun?(); return }
        }
        if event.keyCode == 53 { onEscape?(); return }   // Esc → back to command mode
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
                // Group consecutive ``` fenced lines into a monospaced block;
                // render everything else line-by-line.
                let raw = markdown.components(separatedBy: "\n")
                let groups = Self.group(raw)
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                    if g.isCode {
                        Text(g.text)
                            .font(.system(.callout, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.gray.opacity(0.10)))
                            .textSelection(.enabled)
                    } else {
                        ForEach(Array(ProseMarkdown.lines(g.text).enumerated()), id: \.offset) { _, line in
                            lineView(line)
                        }
                    }
                }
            }
        }
    }

    /// Split markdown into prose vs fenced-code groups (drops the ``` fences).
    static func group(_ lines: [String]) -> [(isCode: Bool, text: String)] {
        var groups: [(Bool, String)] = []
        var buf: [String] = []
        var inCode = false
        func flush(_ code: Bool) {
            if !buf.isEmpty { groups.append((code, buf.joined(separator: "\n"))); buf.removeAll() }
        }
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flush(inCode); inCode.toggle()
            } else { buf.append(line) }
        }
        flush(inCode)
        return groups
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
