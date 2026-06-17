import SwiftUI
import MindoBase
import MindoCore
import MindoMarkdown
import MindoGenAI

/// Which surface the right inspector is showing: the document outline (+ node
/// note), or the cross-document AI assistant.
enum InspectorTab: Sendable { case outline, links, agent }

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
                onConfirm: openSelectedFile
            )
            .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 460)
        } detail: {
            DetailArea(session: $session)
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: inspectorPresented) {
            inspectorPane
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
                if let url = session.activeDocument?.fileURL,
                   let node = sidebarNode(for: url) {
                    sidebarSelection = node
                }
                selectionSource = .pointer
                return
            }
            // Open on selection (single-click, Obsidian-style) but only when
            // the rule says so — skips folders, the already-active file (so
            // the reverse active-doc→selection sync can't loop back into a
            // redundant re-open), and arrow-key traversal (which only moves
            // the highlight; Return opens). See SidebarOpenDecision.
            if SidebarOpenDecision.shouldOpen(
                isFile: new?.isFile ?? false,
                selectedURL: new?.url,
                activeURL: session.activeDocument?.fileURL,
                source: selectionSource
            ), let node = new {
                session.open(url: node.url)
            }
            // Next change is a click again unless an arrow key re-flags it.
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
            guard sidebarSelection == nil,
                  let url = session.activeDocument?.fileURL,
                  let node = sidebarNode(for: url) else { return }
            sidebarSelection = node
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
        + "• Edit the active mind map: get_mindmap (shows each topic's stable [outline-path]), find_topics, "
        + "add_child_topic, add_sibling_topic, rename_topic, remove_topic, move_topic, build_subtree "
        + "(bulk-build from an indented outline), set_topic_attr, set_topic_note/get_topic_note, "
        + "link_topics, set_topic_collapsed; run_lua for anything bespoke.\n"
        + "Target topics by their [outline-path] when you can (stable); fall back to a text query. "
        + "Read before you write. Be concise; when producing a diagram or table, output only valid source."

    /// The right-hand inspector: a toggle between the document Outline (+ node
    /// Note editor) and the cross-document AI Assistant.
    private var inspectorPane: some View {
        Group {
            switch session.inspectorTab {
            case .outline: outlineInspector
            case .links: linksInspector
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
        // Put the Outline / Assistant switch in the inspector's OWN toolbar band
        // (the area at the top that was otherwise empty), not a row below it.
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("", selection: inspectorTabBinding) {
                    Image(systemName: "list.bullet.indent").tag(InspectorTab.outline)
                    Image(systemName: "link").tag(InspectorTab.links)
                    Image(systemName: "bubble.left.and.bubble.right").tag(InspectorTab.agent)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
                .help("Switch the inspector between document outline, linked mentions, and the assistant")
            }
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

    /// The Outline tab content: outline list + (when a node is selected) a
    /// rendered Note editor. The node-properties strip was removed (unused).
    private var outlineInspector: some View {
        VSplitView {
            OutlinePanel(
                items: session.outlineItems,
                selectedTarget: session.selectedOutlineTarget
            ) { item in
                session.requestOutlineNavigation(target: item.target)
            }
            .frame(minHeight: 100, idealHeight: 260)

            // Node-properties strip removed — it wasn't useful.
            // NodePropertyView(properties: session.selectedNodeProperties)
            //     .frame(minHeight: 90)

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
                    MarkdownEditor(text: nodeContentBinding, isDarkMode: colorScheme == .dark)
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
    private func openSelectedFile() {
        guard let node = sidebarSelection,
              SidebarOpenDecision.shouldOpen(
                isFile: node.isFile,
                selectedURL: node.url,
                activeURL: session.activeDocument?.fileURL,
                source: .keyboardConfirm
              ) else { return }
        session.open(url: node.url)
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

