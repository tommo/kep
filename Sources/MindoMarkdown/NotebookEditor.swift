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

    // MARK: - Agent block (a cell-generating author)

    /// The agent cell currently being authored from (set during runAgentCell).
    private var activeAgentCell: String?
    /// The cell id after which the next agent-authored cell is inserted (walks
    /// down as the agent emits cells).
    private var agentInsertAfter: String?
    /// Cells authored by each agent block this session, so a re-run can replace
    /// the previous generation. (In-memory: after a reload the generated cells
    /// are just ordinary cells the user owns; re-running then appends afresh.)
    private var generatedByAgent: [String: [String]] = [:]

    /// Run the agent for an agent cell's prompt. The agent sees the notebook so
    /// far (cells ABOVE this block) as context, researches the KB, and AUTHORS
    /// real prose + code cells immediately below the prompt — editable and
    /// re-runnable like any other cell. Re-running replaces the prior generation.
    func runAgentCell(_ id: String) async {
        guard let runAgent,
              case .agent(_, let prompt, _, _)? = cells.first(where: { $0.id == id }),
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        clearGeneration(of: id)                 // drop the previous run's cells
        setAgentSources(id, [])
        agentTrace[id] = []
        let context = contextAbove(id)
        activeAgentCell = id
        agentInsertAfter = id
        generatedByAgent[id] = []
        running.insert(id); agentBusy = true
        await runAgent(prompt, context, ctx, self)
        running.remove(id); agentBusy = false
        activeAgentCell = nil
        agentInsertAfter = nil
        flushNow()
    }

    /// Remove the cells a previous run of this agent block authored.
    private func clearGeneration(of agentID: String) {
        guard let ids = generatedByAgent[agentID], !ids.isEmpty else { return }
        let set = Set(ids)
        cells.removeAll { set.contains($0.id) }
        generatedByAgent[agentID] = []
    }

    /// Serialize the cells above the agent block as plain context (most-recent
    /// kept, clamped to a budget) so the agent continues the notebook's line of
    /// inquiry instead of starting cold.
    private func contextAbove(_ agentID: String) -> String {
        guard let idx = index(of: agentID), idx > 0 else { return "" }
        var parts: [String] = []
        for cell in cells[0..<idx] {
            switch cell {
            case .prose(_, let t):
                let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { parts.append(s) }
            case .code(_, _, let code):
                let out = outputs.output(forHash: MarkdownExecBlocks.hash(code))
                let tail = out.map { "→ " + ($0.error ?? ($0.text.isEmpty ? "(no output)" : $0.text)) } ?? ""
                parts.append("```lua\n\(code)\n```\n\(tail)")
            case .agent(_, let p, let r, _):
                parts.append("[Earlier agent task: \(p)]" + (r.isEmpty ? "" : "\n\(r)"))
            }
        }
        let joined = parts.joined(separator: "\n\n")
        return joined.count > 6000 ? String(joined.suffix(6000)) : joined
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
    /// Whether this agent block authored cells in the current session (drives
    /// the run vs re-run affordance).
    func hasGenerated(_ id: String) -> Bool { !(generatedByAgent[id]?.isEmpty ?? true) }

    /// Insert an agent-authored cell into the flow, just after the last cell the
    /// agent emitted (or the prompt), and record it so a re-run can replace it.
    private func insertGenerated(_ cell: NotebookCell) {
        if let after = agentInsertAfter, let i = index(of: after) {
            cells.insert(cell, at: i + 1)
        } else {
            cells.append(cell)
        }
        agentInsertAfter = cell.id
        if let a = activeAgentCell { generatedByAgent[a, default: []].append(cell.id) }
        flushNow()
    }

    // NotebookAgentSink — the agent authors REAL, editable cells into the flow.
    func agentAddProse(_ text: String) {
        insertGenerated(.prose(id: freshID("prose"), text: text))
    }
    func agentAddCode(_ code: String, output: ExecOutput?) {
        insertGenerated(.code(id: freshID("code"), language: "lua", code: code))
        if let output { outputs.set(output, forHash: MarkdownExecBlocks.hash(code)) }   // nil → stale until run
        flushNow()
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

/// The SINGLE source of truth for "which cell is being edited" in a notebook.
///
/// The previous design had two uncoordinated authorities — SwiftUI `@FocusState`
/// (which only ever drove the container + the agent field) and the AppKit window
/// first-responder (which the NSTextView cells set imperatively). They drifted,
/// so keystrokes landed on the previously-edited cell. Here the AppKit
/// first-responder is authoritative: each cell editor reports become/resign back
/// to this controller, and the controller is the only thing that initiates
/// edit transitions. `@FocusState` is reduced to a single command-mode flag.
@MainActor
final class NotebookFocusController: ObservableObject {
    /// The cell whose editor currently holds first responder. nil = COMMAND mode
    /// (the command view holds first responder). Set optimistically by
    /// `beginEditing` so a lazily-realized cell renders its editor, then
    /// confirmed by the editor's `becomeFirstResponder`. This is the ONE source
    /// of truth — both block focus (command view) and edit focus (cell editor)
    /// are ordinary AppKit first-responders; no SwiftUI focus involved.
    @Published private(set) var editingCellID: String?

    /// The invisible AppKit view that owns COMMAND-mode keystrokes.
    weak var commandView: NSView?

    private var pendingEdit: String?
    private var views: [String: NotebookCellTextView] = [:]

    /// A cell editor entered the window — track it and, if it's the one we're
    /// waiting to focus (realize race), grab first responder now.
    func register(_ id: String, _ v: NotebookCellTextView) {
        views[id] = v
        if pendingEdit == id, let w = v.window { w.makeFirstResponder(v) }
    }
    func unregister(_ id: String, _ v: NotebookCellTextView) {
        if views[id] === v { views[id] = nil }
    }

    /// Enter EDIT mode on `id`. Optimistic so the row shows its editor even if it
    /// must still be realized; the editor grabs first responder on register.
    func beginEditing(_ id: String) {
        guard editingCellID != id else { return }
        editingCellID = id
        pendingEdit = id
        if let v = views[id], let w = v.window { w.makeFirstResponder(v) }
        // else: the editor grabs first responder when it registers (window-attach)
    }

    /// Enter COMMAND mode — hand first responder to the command view, so arrow
    /// navigation / b·m·g / run keys work. Called on Esc and on focus requests.
    func enterCommandMode() {
        editingCellID = nil
        pendingEdit = nil
        if let cv = commandView, let w = cv.window { w.makeFirstResponder(cv) }
    }

    // Reported up from the actual first-responder — authoritative.
    func didBecomeFirstResponder(_ id: String) { editingCellID = id; pendingEdit = nil }
    func didResignFirstResponder(_ id: String) { /* next begin/enter handles it */ }
    func commandViewBecameFirstResponder() { editingCellID = nil; pendingEdit = nil }
}

/// A command from the notebook's AppKit command view (command-mode keystrokes).
enum NotebookCommand { case selectPrev, selectNext, moveUp, moveDown, edit, run, addCode, addProse, addAgent, delete }

/// Invisible AppKit view that holds first responder in COMMAND mode and turns
/// keystrokes into notebook commands. Block focus lives here (one responder),
/// edit focus lives in the cell editors — never two focus systems at once.
final class NotebookCommandView: NSView {
    weak var controller: NotebookFocusController?
    var onCommand: ((NotebookCommand) -> Void)?
    /// One-shot: grab first responder once we're actually in a window.
    var grabOnAttach = false

    override var acceptsFirstResponder: Bool { true }
    override var focusRingType: NSFocusRingType { get { .none } set {} }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if grabOnAttach, let w = window {
            grabOnAttach = false
            w.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { controller?.commandViewBecameFirstResponder() }
        return ok
    }

    override func keyDown(with e: NSEvent) {
        let opt = e.modifierFlags.contains(.option)
        let runMod = e.modifierFlags.contains(.command) || e.modifierFlags.contains(.shift)
        switch e.keyCode {
        case 126: onCommand?(opt ? .moveUp : .selectPrev); return       // ↑
        case 125: onCommand?(opt ? .moveDown : .selectNext); return     // ↓
        case 36:  onCommand?(runMod ? .run : .edit); return             // ↩ (⌘/⇧ = run)
        case 51, 117: onCommand?(.delete); return                       // ⌫ / ⌦
        default: break
        }
        switch e.charactersIgnoringModifiers {
        case "t": onCommand?(.addProse); return   // Text
        case "c": onCommand?(.addCode); return    // Code
        case "a": onCommand?(.addAgent); return   // Agent
        case "r": onCommand?(.run); return        // Run
        default: super.keyDown(with: e)
        }
    }
}

/// Hosts the command view as a background of the notebook and makes it first
/// responder on appear (unless it's a browse-open).
struct NotebookCommandHost: NSViewRepresentable {
    let controller: NotebookFocusController
    let onCommand: (NotebookCommand) -> Void
    let focusOnAppear: () -> Bool

    func makeNSView(context: Context) -> NotebookCommandView {
        let v = NotebookCommandView()
        v.controller = controller
        v.onCommand = onCommand
        controller.commandView = v
        if focusOnAppear() {
            v.grabOnAttach = true   // consummated in viewDidMoveToWindow
            DispatchQueue.main.async { if v.window != nil { v.window?.makeFirstResponder(v) } }
        }
        return v
    }
    func updateNSView(_ v: NotebookCommandView, context: Context) {
        v.controller = controller
        v.onCommand = onCommand
        controller.commandView = v
    }
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
    @StateObject private var focusCtl = NotebookFocusController()

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
                            NotebookCellRow(model: model, focusCtl: focusCtl, cell: cell,
                                            isSelected: model.selectedID == cell.id,
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
        // Command-mode keystrokes are owned by an AppKit command view (one
        // first-responder chain with the cell editors — no SwiftUI @FocusState).
        .background(NotebookCommandHost(controller: focusCtl,
                                        onCommand: handleCommand,
                                        focusOnAppear: shouldFocusOnAppear))
        .onAppear { model.selectFirstIfNeeded() }
        // Keep the block-selection cursor on whatever cell is being edited
        // (e.g. click-to-edit), so block focus and edit focus never diverge.
        .onChange(of: focusCtl.editingCellID) { _, editing in
            if let editing { model.selectedID = editing }
        }
        .onChange(of: text) { _, new in model.reload(from: new) }
        .onReceive(NotificationCenter.default.publisher(for: .focusNotebookCommand)) { _ in
            model.selectFirstIfNeeded(); focusCtl.enterCommandMode()
        }
    }

    /// Route a command-mode keystroke (from NotebookCommandView) to the model.
    private func handleCommand(_ cmd: NotebookCommand) {
        switch cmd {
        case .selectPrev: model.selectPrev()
        case .selectNext: model.selectNext()
        case .moveUp:     model.moveSelected(by: -1)
        case .moveDown:   model.moveSelected(by: 1)
        case .edit:       if let id = model.selectedID { focusCtl.beginEditing(id) }
        case .run:        Task { await model.runSelected() }
        case .delete:     model.deleteSelected()
        case .addCode:    model.addAfterSelection { model.addCode(after: $0) }; editSelected()
        case .addProse:   model.addAfterSelection { model.addProse(after: $0) }; editSelected()
        case .addAgent:   if model.runAgent != nil { model.addAfterSelection { model.addAgent(after: $0) }; editSelected() }
        }
    }

    /// Drop straight into editing the (just-added) selected cell.
    private func editSelected() {
        if let id = model.selectedID { focusCtl.beginEditing(id) }
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
            Text("↑↓ select · ⏎ edit · ⎋ done · ⌘↩ run · t/c/a new Text/Code/Agent · ⌥↑↓ move · ⌦ delete")
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
    @ObservedObject var focusCtl: NotebookFocusController
    let cell: NotebookCell
    let isSelected: Bool
    var onOpenSource: ((String) -> Void)?

    private var isEditing: Bool { focusCtl.editingCellID == cell.id }

    private var binding: Binding<String> {
        Binding(get: { model.text(of: cell.id) }, set: { model.updateText(cell.id, $0) })
    }

    /// Grow a text editor with its content (no nested scroll); clamp so one huge
    /// cell can't dominate the notebook.
    private func editorHeight(_ s: String, line: CGFloat, min minLines: Int) -> CGFloat {
        let lines = max(minLines, s.components(separatedBy: "\n").count)
        return CGFloat(Swift.min(lines, 30)) * line + 14
    }

    // Uniform chrome label for the cell type (UI text — never confusable with
    // content: tiny, uppercase, tracked, secondary).
    private var typeTag: String {
        switch cell {
        case .prose: return "TEXT"
        case .code:  return "LUA"
        case .agent: return "AGENT"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // The ONLY per-cell decoration: a slim left rule that signals
            // selection (faint) vs editing (full accent). Replaces the old
            // per-type borders, tints and colored backgrounds.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? Color.accentColor.opacity(isEditing ? 1.0 : 0.45) : .clear)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .padding(.trailing, 6)
        // A barely-there wash only while editing, so the active cell is obvious
        // without boxing every cell in.
        .background(isSelected && isEditing ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.selectedID = cell.id })
    }

    // Consistent header for every cell type: type tag · run · ⋯ menu.
    private var header: some View {
        HStack(spacing: 8) {
            Text(typeTag)
                .font(.caption2.weight(.semibold)).tracking(0.6)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            runControl
            cellMenu
        }
    }

    @ViewBuilder private var runControl: some View {
        switch cell {
        case .prose:
            EmptyView()
        case .code:
            if model.running.contains(cell.id) {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await model.run(cell.id) } } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless).help("Run cell (⌘↩)")
            }
        case .agent:
            if model.running.contains(cell.id) {
                ProgressView().controlSize(.small)
            } else {
                let generated = model.hasGenerated(cell.id)
                Button { Task { await model.runAgentCell(cell.id) } } label: {
                    Image(systemName: generated ? "arrow.clockwise" : "play.fill")
                }
                .buttonStyle(.borderless).help(generated ? "Re-run (replaces the cells it wrote)" : "Run research")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch cell {
        case .prose:
            if isEditing {
                NotebookProseView(text: binding, cellID: cell.id, focusCtl: focusCtl,
                                  onEscape: { focusCtl.enterCommandMode() })
                    .frame(height: editorHeight(binding.wrappedValue, line: 19, min: 2))
            } else {
                ProseRenderedView(markdown: model.text(of: cell.id))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedID = cell.id; focusCtl.beginEditing(cell.id) }
            }
        case .code:
            VStack(alignment: .leading, spacing: 4) {
                NotebookCodeView(text: binding, cellID: cell.id, focusCtl: focusCtl,
                                 onRun: { Task { await model.run(cell.id) } },
                                 onEscape: { focusCtl.enterCommandMode() })
                    .frame(height: editorHeight(binding.wrappedValue, line: 18, min: 2))
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.045)))
                outputView
            }
        case .agent:
            agentContent
        }
    }

    /// Agent block content (prompt + authored result). No colored container —
    /// the uniform header's "AGENT" tag identifies it.
    private var agentContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Same NSTextView editor as prose/code (one focus authority). Custom
            // placeholder so an EMPTY prompt reads as a faint hint, not content.
            // ⌘↩ runs the research; plain Return is a newline (multi-line prompts).
            ZStack(alignment: .topLeading) {
                if model.text(of: cell.id).isEmpty {
                    Text("Research question for the agent…  (⌘↩ to run)")
                        .font(.body).italic().foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                NotebookProseView(text: binding, cellID: cell.id, focusCtl: focusCtl,
                                  onRun: { Task { await model.runAgentCell(cell.id) } },
                                  onEscape: { focusCtl.enterCommandMode() })
                    .frame(height: editorHeight(binding.wrappedValue, line: 19, min: 1))
            }
            // The agent AUTHORS its answer as real prose/code cells BELOW this
            // block (editable, re-runnable). What stays here is the task itself
            // plus its provenance: a live step trace and the sources consulted.
            if model.running.contains(cell.id) {
                Text("Researching… (writing cells below)").font(.caption).foregroundStyle(.secondary)
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
                .font(.caption2).foregroundStyle(.secondary)
            }
            let sources = model.agentSources(of: cell.id)
            if !sources.isEmpty {
                HStack(spacing: 4) {
                    Text("SOURCES").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.tertiary)
                    ForEach(sources, id: \.self) { src in
                        if let open = onOpenSource {
                            Button(src) { open(src) }.buttonStyle(.link).font(.caption2)
                        } else {
                            Text(src).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
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
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
        }
    }

    private var cellMenu: some View {
        Menu {
            Button("Move Up") { model.move(cell.id, by: -1) }
            Button("Move Down") { model.move(cell.id, by: 1) }
            Divider()
            Button("Delete Cell", role: .destructive) { model.delete(cell.id) }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(.secondary)
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
    var cellID: String = "?"
    var focusCtl: NotebookFocusController
    var onRun: () -> Void
    var onEscape: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = CodeArea.makeMonospaced(text: text, delegate: context.coordinator) {
            NotebookCodeTextView()
        }
        scroll.hasVerticalScroller = false   // outer notebook ScrollView scrolls
        let cv = tv as? NotebookCodeTextView
        cv?.onRun = onRun
        cv?.onEscape = onEscape
        cv?.cellID = cellID
        cv?.controller = focusCtl
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NotebookCodeTextView else { return }
        if tv.string != text { tv.string = text }
        tv.onRun = onRun
        tv.onEscape = onEscape
        tv.cellID = cellID
        tv.controller = focusCtl
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

/// Proportional plain-text editor for a prose cell, backed by an NSTextView so
/// keyboard focus + typing are reliable — a SwiftUI `TextEditor` inside a
/// `LazyVStack` row frequently fails to take first responder (you couldn't type
/// into a text cell). Esc returns to command mode; everything else is normal.
struct NotebookProseView: NSViewRepresentable {
    @Binding var text: String
    var cellID: String = "?"
    var focusCtl: NotebookFocusController
    /// Optional run action (⌘↩) — used by the agent prompt; nil for plain prose.
    var onRun: (() -> Void)? = nil
    var onEscape: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = CodeArea.makeMonospaced(text: text, delegate: context.coordinator) {
            NotebookProseTextView()
        }
        scroll.hasVerticalScroller = false      // outer notebook ScrollView scrolls
        scroll.drawsBackground = false
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 13)       // proportional — prose, not code
        let pv = tv as? NotebookProseTextView
        pv?.onRun = onRun
        pv?.onEscape = onEscape
        pv?.cellID = cellID
        pv?.controller = focusCtl
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NotebookProseTextView else { return }
        if tv.string != text { tv.string = text }
        tv.onRun = onRun
        tv.onEscape = onEscape
        tv.cellID = cellID
        tv.controller = focusCtl
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

/// Base for the notebook's NSTextView cell editors. First-responder is the
/// SINGLE source of truth: the view registers with the focus controller when it
/// enters the window (consummating a pending edit if it's the awaited cell), and
/// reports become/resign back so the controller's `editingCellID` always matches
/// reality. No imperative "grab focus" guessing — the controller initiates every
/// transition via beginEditing/endEditing.
class NotebookCellTextView: NSTextView {
    var cellID = "?"
    weak var controller: NotebookFocusController?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { controller?.register(cellID, self) }
        else { controller?.unregister(cellID, self) }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { controller?.didBecomeFirstResponder(cellID) }
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { controller?.didResignFirstResponder(cellID) }
        return ok
    }
}

/// NSTextView for a prose / agent-prompt cell: ⌘↩/⇧↩ runs (if a run action is
/// set — agent prompt), Esc → command mode, plain Return inserts a newline.
final class NotebookProseTextView: NotebookCellTextView {
    var onRun: (() -> Void)?
    var onEscape: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, let onRun {   // Return
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if mods == .command || mods == .shift { onRun(); return }
        }
        if event.keyCode == 53 { onEscape?(); return }   // Esc
        super.keyDown(with: event)
    }
}

/// NSTextView that runs its cell on ⌘↩ / ⇧↩ and otherwise behaves normally
/// (plain Return inserts a newline).
final class NotebookCodeTextView: NotebookCellTextView {
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
