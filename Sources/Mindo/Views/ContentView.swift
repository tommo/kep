import SwiftUI
import AppKit
import MindoBase
import MindoCore
import MindoMindMap
import MindoModel
import MindoMarkdown
import MindoGenAI

/// Which surface the right inspector is showing: the document outline (+ node
/// note), or the cross-document AI assistant.
/// Right-inspector top-level mode. `inspector` is an accordion of the passive
/// nav panes (Outline + Linked Mentions, both collapsible); `agent` is the
/// full-pane AI assistant chat.
enum InspectorTab: Sendable { case inspector, agent }

/// Top-level window content: split view (sidebar | detail with outline
/// inspector), plus the global error alert. Owned by `MindoApp.body`.
struct ContentView: View {
    @Binding var session: AppSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var sidebarSelection: NodeData?
    /// What drove the pending selection change. Arrow keys set this to
    /// `.keyboardNavigation` just before the List moves the highlight, so the
    /// open-on-selection rule below can skip them; reset to `.pointer` after
    /// each change so the next click opens as usual.
    @State private var selectionSource: SidebarSelectionSource = .pointer
    /// Presents the node-note editor in a roomy sheet (the inspector strip is
    /// cramped for anything longer than a line or two).
    @State private var noteExpanded = false
    /// Accordion section expansion in the "Inspector" mode (persisted).
    @AppStorage(PrefKeys.inspectorOutlineExpanded) private var outlineExpanded = true
    @AppStorage(PrefKeys.inspectorLinksExpanded) private var linksExpanded = false
    @AppStorage(PrefKeys.inspectorPropertiesExpanded) private var propertiesExpanded = true
    @AppStorage(PrefKeys.inspectorTagsExpanded) private var tagsExpanded = false
    /// Live text of the inspector property/tag query field.
    @State private var tagQuery = ""

    /// Sidebar visibility bridged to `session.sidebarVisible` (toggled from the
    /// View menu / sidebar button). `.all` shows it, `.detailOnly` hides it.
    private var sidebarColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { session.sidebarVisible ? .all : .detailOnly },
            set: { session.sidebarVisible = ($0 != .detailOnly) }
        )
    }

    /// Right inspector presentation bridged to `session.outlineOpen`.
    private var inspectorPresented: Binding<Bool> {
        Binding(get: { session.outlineOpen }, set: { session.outlineOpen = $0 })
    }

    /// A thin accent bar along the TOP edge of the region that holds keyboard
    /// focus (⌘1/2/3/⌘\) — shows focus without boxing in / dimming the content
    /// you're editing. The agent view lives in the inspector, so it lights it too.
    /// The inspector column holds focus whether it's showing the panels or the
    /// agent chat — both light its focus hint.
    private var inspectorRegionFocused: Bool {
        session.activeRegion == .inspector || session.activeRegion == .agent
    }

    @ViewBuilder private func regionRing(_ region: AppSession.FocusRegion) -> some View {
        let active = session.activeRegion == region
            || (region == .inspector && session.activeRegion == .agent)
        VStack(spacing: 0) {
            Rectangle()
                .fill(active ? Color.accentColor : Color.clear)
                .frame(height: 2)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        // Native SwiftUI three-pane layout: NavigationSplitView (sidebar |
        // document) + the purpose-built .inspector (right panel). Both resize and
        // collapse natively — no AppKit NSSplitViewController/NSHostingController
        // hosting, which is what made the panes un-resizable.
        NavigationSplitView(columnVisibility: sidebarColumnVisibility) {
            SidebarView(
                session: $session,
                selection: $sidebarSelection,
                onSelectionSource: { selectionSource = $0 },
                onConfirm: confirmSelection
            )
            .background(RegionContainerTagger(session: session, region: .sidebar))
            .background(WindowConfigurator())
            .overlay(regionRing(.sidebar))
            .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 460)
        } detail: {
            DetailArea(session: $session)
                .background(RegionContainerTagger(session: session, region: .document))
                // Doc focus hint is the tab strip's bottom border (see DetailArea)
                // — a top ring sat under the hidden title bar.
                // Obsidian-style: the tab strip ALWAYS sits flush in the top
                // titlebar row (never a second band). When collapsed the strip
                // reserves a leading gutter for the traffic lights + a single
                // reveal toggle (see DetailArea); the system's own toggle is
                // suppressed below so there's no duplicate control.
                .ignoresSafeArea(.container, edges: .top)
        }
        .navigationSplitViewStyle(.balanced)
        // Kill NavigationSplitView's auto-injected sidebar toggle — it lands in
        // the titlebar leading area and collides with our flush tab strip (a
        // duplicate of the reveal button we draw in the tab row). We provide our
        // own single toggle in DetailArea instead.
        .modifier(SuppressSidebarToggle())
        .inspector(isPresented: inspectorPresented) {
            inspectorPane
                .background(RegionContainerTagger(session: session, region: .inspector))
                // Inspector focus hint is the switch-bar's bottom border (inside).
                .ignoresSafeArea(.container, edges: .top)
                .inspectorColumnWidth(min: 200, ideal: 280, max: 460)
        }
        .onChange(of: sidebarSelection) { _, new in
            // A nil here is almost never a real user deselect — SwiftUI's List
            // clears its selection binding when it resigns first responder, and
            // opening a file does exactly that: the mindmap canvas (and the
            // text editors) grab focus on appear via makeFirstResponder. Treat
            // it as a focus blip and restore the row for the active document so
            // the tree keeps showing where you are (Finder / VS Code behaviour).
            if new == nil {
                // The List nils its binding when it resigns first responder. If
                // the user clicked into the document, re-asserting the row here
                // pulls focus straight back to the workspace panel (the "focus
                // jumps to the sidebar when I click in the doc" bug, most visible
                // with a second tab in front). Defer the decision to the next
                // runloop so the first responder has SETTLED on the new editor —
                // checking synchronously raced and saw focus still in transit.
                selectionSource = .pointer
                DispatchQueue.main.async {
                    guard sidebarSelection == nil, !documentHasFocus,
                          let url = session.activeDocument?.fileURL,
                          let node = sidebarNode(for: url) else { return }
                    sidebarSelection = node
                }
                return
            }
            // Selecting a file — by click OR arrow — browses it: open it WITHOUT
            // taking focus off the sidebar (focusEditor: false), so the List
            // stays first responder and you can keep arrowing through files.
            // Return commits focus to the document (onConfirm). Folders and the
            // already-active file never re-open.
            if let node = new, node.isFile,
               session.activeDocument?.fileURL?.standardizedFileURL != node.url.standardizedFileURL {
                session.open(url: node.url, focusEditor: false)
            }
            selectionSource = .pointer
        }
        // Reverse direction: when the active doc changes (tab click, ⌃⇥
        // cycle, etc.), reflect that selection in the sidebar so the user
        // can see where the doc lives. Skipped when sidebarSelection is
        // already correct to avoid the open→select→open feedback loop.
        .onChange(of: session.activeDocumentID) { _, _ in
            guard let url = session.activeDocument?.fileURL,
                  let node = sidebarNode(for: url),
                  sidebarSelection?.url != node.url else { return }
            sidebarSelection = node
        }
        // Initial sync: .onChange doesn't fire for the value restored at launch,
        // so seed the selection from the active document once the tree exists.
        .onAppear {
            // Keep the focus highlight in sync with the real first responder so
            // clicking (or Tab-ing) into a pane moves it — not only ⌘1/2/3.
            session.startRegionFocusTracking()
            if sidebarSelection == nil,
               let url = session.activeDocument?.fileURL,
               let node = sidebarNode(for: url) {
                sidebarSelection = node
            }
            // Establish a consistent initial focus so the indicator + real
            // first responder agree on launch: the open document, else the tree.
            if session.activeRegion == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    session.focusRegion(session.activeDocument != nil ? .document : .sidebar)
                }
            }
        }
        // Marks the document window as focused so ⌘W (Close Tab) is scoped here
        // and doesn't fire when the Settings window is key.
        .focusedSceneValue(\.documentSceneActive, true)
        .alert(L("error.alert_title"), isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("OK") { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }

    private var inspectorTabBinding: Binding<InspectorTab> {
        Binding(get: { session.inspectorTab }, set: { session.inspectorTab = $0 })
    }

    /// System prompt for the assistant — framed as a whole-workspace agent
    /// rather than a single-document helper.
    static let agentSystemPrompt =
        "You are Mindo's assistant for the user's entire knowledge base — multiple mind maps and "
        + "Markdown/PlantUML/CSV documents linked by [[wiki links]]. You are not tied to one document. "
        + "You have a comprehensive toolset; prefer tools over guessing:\n"
        + "• Explore: list_docs, search_workspace (literal text/regex), semantic_search (meaning-based "
        + "retrieval — use when you don't know the exact wording), read_document, read_section, "
        + "document_outline, resolve_link, backlinks, outgoing_links.\n"
        + "• Edit documents on disk: create_document, overwrite_document, append_to_document, "
        + "replace_section, insert_after_heading.\n"
        + "• Edit the active mind map: get_mindmap (shows each topic's stable [outline-path]), get_subtree "
        + "(inspect one region of a large map), find_topics, "
        + "add_child_topic, add_sibling_topic, rename_topic, remove_topic, move_topic, build_subtree "
        + "(bulk-build from an indented outline), sort_children, set_topic_attr, "
        + "set_topic_note/get_topic_note, link_topics, set_topic_collapsed; run_lua for anything bespoke.\n"
        + "Target topics by their [outline-path] when you can (stable); fall back to a text query. "
        + "Read before you write. Be concise; when producing a diagram or table, output only valid source."

    /// The right-hand inspector: a toggle between the document Outline (+ node
    /// Note editor) and the cross-document AI Assistant.
    private var inspectorPane: some View {
        VStack(spacing: 0) {
            // Inspector / Assistant switch — a small inline bar at the top of the
            // inspector. (Was a window toolbar item, but hiding the title bar left
            // that toolbar band as empty space above the doc tabs.)
            HStack {
                Picker("", selection: inspectorTabBinding) {
                    Image(systemName: "sidebar.squares.right").tag(InspectorTab.inspector)
                    Image(systemName: "bubble.left.and.bubble.right").tag(InspectorTab.agent)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
                .help("Switch the inspector between the document panels (outline + linked mentions) and the assistant")
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // Bottom border of the switch bar = inspector focus hint (accent when
            // the inspector/agent region holds focus).
            Rectangle()
                .fill(inspectorRegionFocused ? Color.accentColor : Color(nsColor: .separatorColor))
                .frame(height: 2)   // constant height — only the COLOR changes (no layout shift on focus)
            Group {
                switch session.inspectorTab {
                case .inspector: accordionInspector
                case .agent:
                    DialogView(
                        systemPrompt: Self.agentSystemPrompt,
                        contextProvider: { session.aiWorkspaceContextBlock() },
                        onInsert: { session.insertDialogReply($0) },
                        agentReply: { try await session.agentReply($0) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $noteExpanded) {
            NoteEditorSheet(
                text: nodeContentBinding,
                isDarkMode: colorScheme == .dark,
                title: session.selectedNodeProperties?.title
            )
        }
    }

    /// The Links tab: "Linked mentions" — every workspace document that
    /// references the active document via a [[wiki link]], with the context line
    /// of each mention. Click a source to open it.
    private var linksInspector: some View {
        let mentions = session.linkedMentions()
        let total = mentions.reduce(0) { $0 + $1.snippets.count }
        return Group {
            if session.activeDocument?.fileURL == nil {
                ContentUnavailableView("No document", systemImage: "link",
                                       description: Text("Open a saved document to see what links to it."))
            } else if mentions.isEmpty {
                ContentUnavailableView("No linked mentions", systemImage: "link",
                                       description: Text("No other document links to this one with [[wiki links]] yet."))
            } else {
                List {
                    Section {
                        ForEach(mentions, id: \.source) { mention in
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    session.open(url: mention.source)
                                } label: {
                                    Label(mention.source.deletingPathExtension().lastPathComponent,
                                          systemImage: "doc.text")
                                        .font(.callout.weight(.medium))
                                }
                                .buttonStyle(.link)
                                ForEach(Array(mention.snippets.enumerated()), id: \.offset) { _, snippet in
                                    Text(snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("\(total) mention\(total == 1 ? "" : "s") from \(mentions.count) document\(mentions.count == 1 ? "" : "s")")
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Tag list for the active mind map: each distinct tag + how many nodes
    /// carry it; clicking selects all of them on the canvas.
    private var tagsInspector: some View {
        let tags = session.activeMindMapTagCounts
        return VStack(alignment: .leading, spacing: 4) {
            // Query bar: `key:value` / `#tag` / text, space = AND. Return selects
            // every matching node on the canvas (#203 property queries).
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                TextField(L("inspector.query.placeholder"), text: $tagQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { session.selectTopicsMatching(tagQuery) }
                    .help(L("inspector.query.help"))
                Menu {
                    if !tagQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button(L("inspector.query.save")) { session.saveQuery(name: tagQuery, query: tagQuery) }
                        Divider()
                    }
                    if session.savedQueries.isEmpty {
                        Text(L("inspector.query.none"))
                    } else {
                        ForEach(session.savedQueries) { q in
                            Menu(q.name) {
                                Button(L("inspector.query.run")) {
                                    tagQuery = q.query; session.selectTopicsMatching(q.query)
                                }
                                Button(L("inspector.query.remove"), role: .destructive) {
                                    session.removeSavedQuery(q)
                                }
                            }
                        }
                    }
                } label: { Image(systemName: "bookmark") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(L("inspector.query.saved_help"))
            }
            .padding(.horizontal, 8).padding(.top, 4)
            // While a query is typed, show its results (Bases-style view); else
            // the tag list.
            if tagQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                tagList(tags)
            } else {
                queryResults
            }
        }
    }

    /// Live results of the inspector query: matching nodes as clickable rows
    /// (click navigates the canvas to that node). #203 query view.
    private var queryResults: some View {
        let results = session.queryResults(tagQuery)
        return Group {
            if results.isEmpty {
                Text(L("inspector.query.no_results"))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: L("inspector.query.count_fmt"), results.count))
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.bottom, 2)
                    ForEach(results, id: \.path) { row in
                        Button { session.requestOutlineNavigation(target: row.path) } label: {
                            HStack(spacing: 6) {
                                Label(row.text, systemImage: "smallcircle.filled.circle")
                                    .font(.callout).lineLimit(1)
                                if !row.markers.isEmpty {
                                    Spacer(minLength: 4)
                                    ForEach(Array(row.markers.enumerated()), id: \.offset) { _, marker in
                                        Image(systemName: marker.symbolName)
                                            .font(.caption2)
                                            .foregroundStyle(markerTint(marker.role))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 8).padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// SwiftUI mirror of the canvas marker tints (MindMapView+Drawing) so the
    /// results list reads consistently with the nodes it points at.
    private func markerTint(_ role: PropertyMarker.Role) -> Color {
        switch role {
        case .priority(let p):
            switch p {
            case 1: return .red
            case 2: return .orange
            case 3: return .yellow
            case 4: return .blue
            default: return .gray
            }
        case .doneTrue:  return .green
        case .doneFalse: return .secondary
        case .tags:      return .secondary
        case .progress:  return .blue
        }
    }

    @ViewBuilder private func tagList(_ tags: [(tag: String, count: Int)]) -> some View {
        Group {
            if tags.isEmpty {
                Text(L("inspector.tags.empty"))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tags, id: \.tag) { entry in
                        Button { session.selectTopicsWithTag(entry.tag) } label: {
                            HStack(spacing: 6) {
                                Label(entry.tag, systemImage: "tag")
                                    .font(.callout).lineLimit(1)
                                Spacer()
                                Text("\(entry.count)").font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .help(L("inspector.tags.select_help"))
                    }
                }
            }
        }
    }

    /// "Inspector" mode: an accordion of the two passive nav panes — the
    /// document Outline and the Linked Mentions — each independently
    /// collapsible so both can be visible at once (Obsidian-style), unlike the
    /// old one-at-a-time tabs. The chat lives in its own full pane (`.agent`).
    private var accordionInspector: some View {
        VStack(spacing: 0) {
            CollapsibleInspectorSection(title: L("detail.outline.title"),
                                        systemImage: "list.bullet.indent",
                                        isExpanded: $outlineExpanded) {
                outlineInspector
            }
            // The typed-properties panel only applies to a selected mind-map
            // node; hide it entirely for other doc types / no selection.
            if session.selectedTopic != nil {
                Divider()
                CollapsibleInspectorSection(title: L("inspector.properties"),
                                            systemImage: "tablecells",
                                            isExpanded: $propertiesExpanded) {
                    NodePropertiesView(session: $session,
                                       properties: session.selectedNodeUserProperties)
                }
            }
            // Document-wide tag list (mind maps): click a tag to select every
            // node carrying it.
            if session.activeFileType == .mindMap {
                Divider()
                CollapsibleInspectorSection(title: L("inspector.tags"),
                                            systemImage: "tag",
                                            isExpanded: $tagsExpanded) {
                    tagsInspector
                }
            }
            Divider()
            CollapsibleInspectorSection(title: L("inspector.linked_mentions"),
                                        systemImage: "link",
                                        isExpanded: $linksExpanded) {
                linksInspector
            }
            if !outlineExpanded && !linksExpanded && !propertiesExpanded && !tagsExpanded { Spacer() }
        }
    }

    /// The Outline tab content: outline list + (when a node is selected) a
    /// rendered Note editor. The node-properties strip was removed (unused).
    private var outlineInspector: some View {
        VSplitView {
            OutlinePanel(
                items: session.outlineItems,
                selectedTarget: session.selectedOutlineTarget,
                onSelect: { item in session.requestOutlineNavigation(target: item.target) },
                // Inline rename is only meaningful for mind maps (a topic's text);
                // markdown/PlantUML outline rows map to read-only source offsets.
                onRename: session.activeFileType == .mindMap
                    ? { item, newName in session.renameOutlineTopic(atOutlinePath: item.target, to: newName) }
                    : nil,
                onMove: session.activeFileType == .mindMap
                    ? { item, move in session.moveOutlineTopic(atOutlinePath: item.target, move) }
                    : nil,
                onToggleCollapse: session.activeFileType == .mindMap
                    ? { item in session.toggleOutlineCollapse(atOutlinePath: item.target) }
                    : nil
            )
            .frame(minHeight: 100, idealHeight: 260)

            // Node content editor — the SAME markdown widget the .md document
            // view uses, bound to the selected node's content (its Note).
            if session.selectedNodeProperties != nil {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text(L("inspector.note")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { noteExpanded = true } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.plain)
                        .help(L("inspector.note.expand"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    Divider()
                    MarkdownEditor(text: nodeContentBinding, isDarkMode: colorScheme == .dark,
                                   showsModeSwitch: false)
                        .id(session.selectedOutlineTarget)
                        .frame(maxHeight: .infinity)
                }
                .frame(minHeight: 160, maxHeight: .infinity)
            }
        }
    }

    /// Two-way binding to the selected node's markdown content (its Note).
    private var nodeContentBinding: Binding<String> {
        Binding(
            get: { session.selectedNodeContent ?? "" },
            set: { session.setSelectedNodeContent($0) }
        )
    }

    /// Open the currently-highlighted sidebar file (Return key, R6). Honours
    /// the same file/folder/active-doc guards as click-to-open.
    /// Return key in the sidebar: commit focus to the document. The file is
    /// already open from selection (browse); if somehow not, open it with focus.
    /// True when the window's first responder is the document editor (mindmap
    /// canvas or any text view — doc editor, inspector note editor, agent input)
    /// rather than the sidebar tree. Used to stop the sidebar from grabbing focus
    /// back when the user clicks into the document.
    private var documentHasFocus: Bool {
        guard let fr = (NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder else { return false }
        if fr is NSText { return true }          // any text editor (doc / note / agent)
        if let v = fr as? NSView {
            if v is MindMapView { return true }  // the canvas itself
            if let canvas = session.activeMindMapView,
               v == canvas || v.isDescendant(of: canvas) { return true }
        }
        return false
    }

    private func confirmSelection() {
        guard let node = sidebarSelection, node.isFile else { return }
        if session.activeDocument?.fileURL?.standardizedFileURL == node.url.standardizedFileURL {
            session.focusActiveEditor()
        } else {
            session.open(url: node.url, focusEditor: true)
        }
    }

    /// Walk every workspace tree looking for the node whose URL matches.
    /// Used for sidebar reveal-on-tab. Loaded children only — files
    /// inside collapsed folders won't be found, but that's the right
    /// trade-off (auto-expanding folders to reveal a tab would be loud).
    private func sidebarNode(for url: URL) -> NodeData? {
        for root in session.workspaceRoots {
            if let hit = findNode(in: root, matching: url) { return hit }
        }
        return nil
    }

    private func findNode(in node: NodeData, matching url: URL) -> NodeData? {
        if node.url.standardizedFileURL == url.standardizedFileURL { return node }
        guard node.isExpandable else { return nil }
        for child in node.children() {
            if let hit = findNode(in: child, matching: url) { return hit }
        }
        return nil
    }
}

/// Invisible probe placed as a `.background` of each window region. Once in the
/// view hierarchy it hands its enclosing container view to the session, which
/// uses it to map the first responder back to a region (so the focus highlight
/// follows mouse clicks and Tab, not just the ⌘1/2/3 shortcuts).
private struct RegionContainerTagger: NSViewRepresentable {
    let session: AppSession
    let region: AppSession.FocusRegion

    func makeNSView(context: Context) -> TaggerNSView {
        let v = TaggerNSView()
        v.onAttach = { container in
            session.registerRegionContainer(container, as: region)
        }
        return v
    }

    func updateNSView(_ nsView: TaggerNSView, context: Context) {
        // Re-assert in case SwiftUI re-parents the region's host view.
        if let container = nsView.superview {
            session.registerRegionContainer(container, as: region)
        }
    }

    final class TaggerNSView: NSView {
        var onAttach: ((NSView) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // `.background` makes this a sibling of the region content under a
            // shared container — our superview — which is therefore an ancestor
            // of whatever responder the user clicks inside the region.
            if window != nil, let container = superview { onAttach?(container) }
        }
    }
}

/// One collapsible pane of the right-inspector accordion: a clickable header
/// (chevron + title) and, when expanded, its content filling the available
/// height. Collapsed sections shrink to the header so siblings get the space.
private struct CollapsibleInspectorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 10)
                    Label(title, systemImage: systemImage)
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            if isExpanded {
                content().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: isExpanded ? .infinity : nil)
    }
}


/// Suppresses NavigationSplitView's automatically generated sidebar toggle
/// (macOS 14.4+). On older systems it's a no-op — the toggle stays, which is
/// harmless since the deployment floor in practice is current macOS.
private struct SuppressSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.4, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

/// Takes direct AppKit control of the host `NSWindow`: keeps the title bar
/// transparent/empty (no app-name band) and strips NavigationSplitView's
/// auto-injected toolbar (the sidebar-toggle item that floats over our flush
/// tab strip). SwiftUI's `.toolbar(removing: .sidebarToggle)` does NOT remove
/// it under `.windowStyle(.hiddenTitleBar)`, so we do it at the window level.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { Self.configure(v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView.window) }
    }

    static func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // NavigationSplitView injects an NSToolbar holding a flexible space, its
        // own sidebar-toggle, and a split-view tracking separator. Under
        // `.hiddenTitleBar` that toggle floats over our flush tab strip as a
        // stray rounded button, and `.toolbar(removing: .sidebarToggle)` does
        // NOT remove it. We draw our own toolbar/tab row, so drop the SwiftUI
        // toolbar entirely at the window level. Guard so we only clear it once
        // (SwiftUI rarely re-adds it, but the guard avoids any churn if it does).
        if window.toolbar != nil {
            window.toolbar = nil
        }
    }
}
