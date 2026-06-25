import SwiftUI
import Combine
import KepBase

/// Observable state for an open notebook: the ordered cells, cached outputs,
/// and which cells are mid-run. Edits mutate cells in place (stable ids), then
/// debounce-serialize back to the document text. Lives in KepMarkdown (pure);
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
        seedRanHashFromOutputs()
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
        let id = freshID("code")
        insertGenerated(.code(id: id, language: "lua", code: code))
        if let output {
            let h = MarkdownExecBlocks.hash(code)
            outputs.set(output, forHash: h)
            ranHash[id] = h            // bind so the authored cell shows its output
        }                              // nil → stale until run
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
        seedRanHashFromOutputs()
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

    /// The hash of the code each cell actually RAN this session. Outputs are
    /// content-addressed (shared sidecar), so without this, editing a cell to
    /// match any previously-run code — its own old text or another cell's —
    /// would resurrect that cached output as if you'd re-run it. We instead bind
    /// a cell's displayed output to what THIS cell last ran: editing to anything
    /// other than the exact ran text shows "stale" (no output) until you re-run.
    /// Empty on a freshly-opened notebook, where we fall back to the persisted
    /// sidecar so saved outputs still show.
    private var ranHash: [String: String] = [:]

    /// Seed the run-binding from persisted outputs on load: a saved notebook's
    /// cells match their saved outputs, so each code cell "ran" its current text.
    /// After this, only an EDIT (which changes the hash) makes a cell stale —
    /// matching some other cached hash never resurrects an output.
    private func seedRanHashFromOutputs() {
        ranHash.removeAll()
        for case .code(let id, _, let code) in cells where outputs.output(forHash: MarkdownExecBlocks.hash(code)) != nil {
            ranHash[id] = MarkdownExecBlocks.hash(code)
        }
    }

    func output(for id: String) -> ExecOutput? {
        guard case .code(_, _, let code)? = cells.first(where: { $0.id == id }) else { return nil }
        // Show output ONLY for the exact code this cell ran/loaded — never just
        // because some other cell's run left a matching hash in the shared cache.
        return ranHash[id] == MarkdownExecBlocks.hash(code) ? outputs.output(forHash: ranHash[id]!) : nil
    }
    func isStale(_ id: String) -> Bool {
        guard case .code(_, _, let code)? = cells.first(where: { $0.id == id }) else { return false }
        return ranHash[id] != MarkdownExecBlocks.hash(code)
    }

    func run(_ id: String) async {
        guard case .code(_, _, let code)? = cells.first(where: { $0.id == id }) else { return }
        running.insert(id)
        let out = await runOne(code, ctx)
        let h = MarkdownExecBlocks.hash(code)
        outputs.set(out, forHash: h)
        ranHash[id] = h
        running.remove(id)
    }

    func runAllCells() async {
        let nb = Notebook(cells: cells)
        let ids = nb.codeCells.map(\.id)
        running.formUnion(ids)
        outputs = await runAll(nb, ctx)
        for case .code(let cid, _, let code) in nb.cells { ranHash[cid] = MarkdownExecBlocks.hash(code) }
        running.subtract(ids)
    }

    func clearOutputs() {
        outputs = ExecOutputs()
        ranHash.removeAll()
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
                                            isDark: isDarkMode, onOpenSource: onOpenSource)
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
    var isDark: Bool = false
    var onOpenSource: ((String) -> Void)?

    private var isEditing: Bool { focusCtl.editingCellID == cell.id }

    private var binding: Binding<String> {
        Binding(get: { model.text(of: cell.id) }, set: { model.updateText(cell.id, $0) })
    }

    /// The cell's one editor sizes itself to its laid-out content (reported via
    /// onHeight) so there's no painful inner scroll — including soft-wrapped lines.
    @State private var measuredEditorHeight: CGFloat = 44
    /// Bumped on a live editor-theme change to re-resolve rendered-markdown colors.
    @State private var themeTick = 0

    /// TWO independent cues, two channels — never conflated:
    ///   • the left RULE = block TYPE, always (no bar for Text, neutral for Code,
    ///     purple for Agent). It does NOT change with selection.
    /// Three distinct states, three cues:
    ///   • selected (command cursor) → a faint background WASH.
    ///   • editing → an accent BORDER that "contains" the cell, so it reads as a
    ///     box you're inside and ⎋ (escape) to step out of is intuitive.
    ///   • idle → nothing but the type rule.
    /// No buttons or menus — run ⌘↩ / Run All, move ⌥↑↓, delete ⌦.
    private var ruleColor: Color {
        switch cell {
        case .prose: return .clear
        case .code:  return Color.secondary.opacity(0.4)
        case .agent: return Color.purple.opacity(0.55)
        }
    }
    private var selectionWash: Color {
        guard isSelected, !isEditing else { return .clear }   // wash = selected-not-editing
        return Color.accentColor.opacity(0.16)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(ruleColor)
                .frame(width: 3)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(selectionWash))
        // Editing draws a contained accent box (⎋ to leave); selection is a wash.
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .opacity(isEditing ? 1 : 0)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            model.selectedID = cell.id
            // A single click on now-selectable rendered prose otherwise hands
            // first responder to the text view, stealing the arrow keys from
            // NotebookCommandView. Re-assert command focus so ↑/↓ block-nav
            // survives a click (drag-to-select-text doesn't fire a TapGesture).
            if !isEditing { focusCtl.enterCommandMode() }
        })
        .onReceive(NotificationCenter.default.publisher(for: .editorThemeChanged)) { _ in themeTick += 1 }
    }

    @ViewBuilder private var content: some View {
        switch cell {
        case .prose:
            if isEditing {
                NotebookProseView(text: binding, cellID: cell.id, focusCtl: focusCtl,
                                  onHeight: { measuredEditorHeight = $0 },
                                  onEscape: { focusCtl.enterCommandMode() })
                    .frame(height: measuredEditorHeight)
            } else {
                let md = model.text(of: cell.id)
                if md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Selection + ⏎-to-edit is handled by the row's tap gesture —
                    // no own tap handler (it would race the command-focus re-assert
                    // and break arrow nav). Keyboard-first: select, then ⏎.
                    Text("Empty — ⏎ to write…").italic().foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Native markdown (swift-markdown AST) — selectable, themed,
                    // wiki-links clickable; replaces the hand-rolled line renderer.
                    // ⏎ to edit (the row tap selects + keeps block-nav focus;
                    // drag still selects text). `themeTick` re-resolves on theme change.
                    let _ = themeTick
                    let st = MarkdownRenderStyle.resolved(dark: isDark)
                    MarkdownBlocksView(blocks: NativeMarkdownRenderer.blocks(md, style: st, linkifyWiki: true),
                                       style: st,
                                       onOpenWikiLink: { target, _ in onOpenSource?(target) })
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .code:
            let out = model.output(for: cell.id)
            VStack(alignment: .leading, spacing: 4) {
                NotebookCodeView(text: binding, cellID: cell.id, isDark: isDark,
                                 errorLine: out?.error != nil ? out?.errorLine : nil,
                                 focusCtl: focusCtl,
                                 onHeight: { measuredEditorHeight = $0 },
                                 onRun: { Task { await model.run(cell.id) } },
                                 onEscape: { focusCtl.enterCommandMode() })
                    .frame(height: measuredEditorHeight)
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
                                  onHeight: { measuredEditorHeight = $0 },
                                  onRun: { Task { await model.runAgentCell(cell.id) } },
                                  onEscape: { focusCtl.enterCommandMode() })
                    .frame(height: measuredEditorHeight)
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
            VStack(alignment: .leading, spacing: 4) {
                // Any captured stdout (present even when the cell later errored).
                if !out.text.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if out.error == nil, model.isStale(cell.id) {
                            Text("stale — re-run").font(.caption2).foregroundStyle(.orange)
                        }
                        Text(out.text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                }
                if let err = out.error { errorBox(err, line: out.errorLine) }
            }
        }
    }

    /// A readable Lua-error panel: an icon + ERROR tag + a "line N" badge, then
    /// the clean message (no LuaSwift wrapper noise). Visually distinct from
    /// normal output so a failure is unmistakable.
    @ViewBuilder private func errorBox(_ message: String, line: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                Text("ERROR").font(.caption2.weight(.bold)).tracking(0.6)
                if let line {
                    Text("line \(line)").font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.red.opacity(0.18)))
                }
                if model.isStale(cell.id) { Text("· edited since").font(.caption2).foregroundStyle(.orange) }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.red)
            Text(message)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.red.opacity(0.25)))
    }
}

/// Monospaced Lua source editor for a code cell that runs the cell from the
/// keyboard — ⌘↩ or ⇧↩ (Jupyter-style), so notebooks aren't mouse-only.
/// Backed by an NSTextView (SwiftUI TextEditor can't intercept those keys).
/// Laid-out content height of a text view — accounts for SOFT-WRAPPED lines (a
/// `\n` count doesn't), clamps to a generous cap, and toggles the inner scroller
/// only past that cap. Callers on the main thread.
private func notebookContentHeight(_ tv: NSTextView, cap: CGFloat = 700) -> CGFloat {
    guard let lm = tv.layoutManager, let tc = tv.textContainer else { return 30 }
    lm.ensureLayout(for: tc)
    let used = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2 + 3
    tv.enclosingScrollView?.hasVerticalScroller = used > cap
    return Swift.min(Swift.max(used, 30), cap)
}

struct NotebookCodeView: NSViewRepresentable {
    @Binding var text: String
    var cellID: String = "?"
    var isDark: Bool = false
    /// 1-based line the cell's last run errored on (nil = no current error) —
    /// tinted in the editor so the "line N" badge points at something.
    var errorLine: Int?
    var focusCtl: NotebookFocusController
    /// Report the editor's laid-out height so the cell can size to fit (no inner
    /// scroll for normal cells).
    var onHeight: (CGFloat) -> Void = { _ in }
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
        context.coordinator.dark = isDark
        context.coordinator.errorLine = errorLine
        context.coordinator.onHeight = onHeight
        context.coordinator.highlight(tv)
        context.coordinator.measure(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NotebookCodeTextView else { return }
        let changed = tv.string != text
        if changed { tv.string = text }
        tv.onRun = onRun
        tv.onEscape = onEscape
        tv.cellID = cellID
        tv.controller = focusCtl
        context.coordinator.onHeight = onHeight
        if changed || context.coordinator.dark != isDark || context.coordinator.errorLine != errorLine {
            context.coordinator.dark = isDark
            context.coordinator.errorLine = errorLine
            context.coordinator.highlight(tv)
        }
        context.coordinator.measure(tv)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        weak var textView: NSTextView?
        var dark = false
        var errorLine: Int?
        var onHeight: ((CGFloat) -> Void)?
        init(text: Binding<String>) { self.text = text }
        func measure(_ tv: NSTextView) {
            let h = notebookContentHeight(tv)
            DispatchQueue.main.async { [weak self] in self?.onHeight?(h) }
        }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, tv.string != text.wrappedValue else { return }
            text.wrappedValue = tv.string
            // An edit invalidates the cached error → drop the error tint as we
            // re-highlight (the cell is now stale until re-run).
            errorLine = nil
            highlight(tv)
            measure(tv)
        }
        func highlight(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            LuaHighlighter.apply(to: storage, dark: dark,
                                 font: tv.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular))
            // Tint the offending line on top of the syntax colors.
            if let line = errorLine, let r = Self.range(ofLine: line, in: tv.string as NSString) {
                storage.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.16), range: r)
            }
        }
        /// UTF-16 range of the 1-based `line` (including its terminator).
        static func range(ofLine line: Int, in ns: NSString) -> NSRange? {
            guard line >= 1 else { return nil }
            var n = 1, loc = 0
            while loc <= ns.length {
                let r = ns.lineRange(for: NSRange(location: loc, length: 0))
                if n == line { return r }
                n += 1
                loc = NSMaxRange(r)
                if r.length == 0 { break }
            }
            return nil
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
    var onHeight: (CGFloat) -> Void = { _ in }
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
        context.coordinator.onHeight = onHeight
        context.coordinator.measure(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NotebookProseTextView else { return }
        if tv.string != text { tv.string = text }
        tv.onRun = onRun
        tv.onEscape = onEscape
        tv.cellID = cellID
        tv.controller = focusCtl
        context.coordinator.onHeight = onHeight
        context.coordinator.measure(tv)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        weak var textView: NSTextView?
        var onHeight: ((CGFloat) -> Void)?
        init(text: Binding<String>) { self.text = text }
        func measure(_ tv: NSTextView) {
            let h = notebookContentHeight(tv)
            DispatchQueue.main.async { [weak self] in self?.onHeight?(h) }
        }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, tv.string != text.wrappedValue else { return }
            text.wrappedValue = tv.string
            measure(tv)
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
