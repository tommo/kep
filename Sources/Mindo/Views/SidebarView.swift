import SwiftUI
import MindoCore

/// Workspaces + lazy folder/file tree on the left of the window.
struct SidebarView: View {
    @Binding var session: AppSession
    @Binding var selection: NodeData?
    @AppStorage(PrefKeys.sidebarSortMode) private var sortModeRaw = SidebarSortMode.name.rawValue
    /// Records what drove the next selection change so ContentView can tell
    /// arrow-key traversal (highlight only) apart from a click (opens).
    var onSelectionSource: (SidebarSelectionSource) -> Void = { _ in }
    /// Return on the highlighted row — opens it (R6).
    var onConfirm: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("sidebar.workspaces")).font(.headline)
                Spacer()
                Menu {
                    Picker(L("sidebar.sort.label"), selection: $sortModeRaw) {
                        ForEach(SidebarSortMode.allCases, id: \.rawValue) { mode in
                            Text(L(.init(stringLiteral: "sidebar.sort.\(mode.rawValue)"))).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("sidebar.sort.label"))
                Button { session.openWorkspace() } label: {
                    Image(systemName: "plus")
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if !session.workspaceRoots.isEmpty {
                FileTypeFilterBar(filter: $session.sidebarTypeFilter)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            if session.workspaceRoots.isEmpty {
                ContentUnavailableView(
                    L("sidebar.empty.title"),
                    systemImage: "folder",
                    description: Text(L("sidebar.empty.description"))
                )
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    // No Section wrapper — the `.sidebar` style indents Section
                    // content by a large fixed amount (the "wasteful" gap). A
                    // plain header row + the children gives us full control of
                    // the workspace→child indent (see NodeRow.rowInsets).
                    ForEach(session.workspaceRoots, id: \.self) { root in
                        workspaceHeaderRow(root)
                        NodeRow(node: root, session: $session, selection: $selection, depth: 0)
                    }
                }
                .listStyle(.sidebar)
                .environment(\.defaultMinListRowHeight, 15)
                .controlSize(.small)
                // Arrow keys move the highlight only — flag the source so the
                // open-on-selection wiring skips them (#21). `.ignored` lets
                // the List perform its own arrow navigation afterwards.
                // Up/down are handled natively by the List — moving the
                // selection browse-opens the file (see ContentView.onChange).
                // Left collapses / right expands the highlighted folder or
                // workspace (Finder/Obsidian behaviour).
                .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                    guard let node = selection, node.isExpandable else { return .ignored }
                    let expanded = session.isFolderExpanded(node.url, isWorkspace: node.isWorkspace)
                    if press.key == .leftArrow, expanded {
                        session.setFolderExpanded(node.url, isWorkspace: node.isWorkspace, false)
                        return .handled
                    }
                    if press.key == .rightArrow, !expanded {
                        session.setFolderExpanded(node.url, isWorkspace: node.isWorkspace, true)
                        return .handled
                    }
                    return .ignored
                }
                // Return opens the highlighted file (R6).
                .onKeyPress(.return) {
                    onConfirm()
                    return .handled
                }
                // NodeData is a reference type SwiftUI doesn't observe; rebuild
                // the tree when a reload bumps this token (new files appearing,
                // e.g. the agent creating documents).
                .id(session.sidebarReloadToken)
            }
        }
    }

    /// One workspace's header row: a fold toggle (chevron + tinted vault icon +
    /// name) and a remove button. A plain List row (not a Section header), so
    /// the contents below aren't pushed right by the sidebar's section indent.
    @ViewBuilder
    private func workspaceHeaderRow(_ root: NodeData) -> some View {
        HStack {
            Button {
                let cur = session.isFolderExpanded(root.url, isWorkspace: true)
                session.setFolderExpanded(root.url, isWorkspace: true, !cur)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: session.isFolderExpanded(root.url, isWorkspace: true)
                          ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 10)
                    Image(systemName: "books.vertical.fill").foregroundStyle(Color.accentColor)
                    Text(root.name).font(.headline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("sidebar.tooltip.toggle_workspace"))
            Spacer()
            Button { session.removeWorkspace(root) } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .help(L("sidebar.tooltip.remove_workspace"))
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 6))
        .onDrag { NSItemProvider(object: root.url.path as NSString) }
        .onDrop(of: [.text], delegate: WorkspaceDropDelegate(target: root.url.path, session: $session))
    }
}

/// Toggle bar that drives the file-type filter. Empty selection means
/// no filter (all files visible). Folders are always shown so the user
/// can navigate.
private struct FileTypeFilterBar: View {
    @Binding var filter: Set<SupportedFileType>

    private static let displayed: [SupportedFileType] = [
        .mindMap, .markdown, .plantUML, .csv, .plainText
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.displayed, id: \.self) { type in
                Button {
                    if filter.contains(type) { filter.remove(type) }
                    else { filter.insert(type) }
                } label: {
                    Image(systemName: type.sfSymbolName)
                        .frame(width: 18, height: 18)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(filter.contains(type) ? Color.accentColor.opacity(0.25) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(type.rawValue.uppercased())
            }
            if !filter.isEmpty {
                Button { filter.removeAll() } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .help(L("sidebar.filter.clear"))
            }
            Spacer()
        }
    }
}

/// Drop target for the workspace headers — pulls the dragged workspace's
/// path out of the item provider and asks AppSession to swap them.
private struct WorkspaceDropDelegate: DropDelegate {
    let target: String
    @Binding var session: AppSession

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let source = obj as? String, source != target else { return }
            DispatchQueue.main.async {
                session.reorderWorkspace(from: source, to: target)
            }
        }
        return true
    }
}

/// Inline TextField that replaces a workspace row's static label while
/// the user renames. Commits on Return; cancels on Esc or empty submit.
/// Auto-focuses on appear via @FocusState.
private struct InlineRenameField: View {
    let initial: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @FocusState private var focused: Bool

    init(initial: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onCommit = onCommit
        self.onCancel = onCancel
        _name = State(initialValue: initial)
    }

    var body: some View {
        TextField("", text: $name, onCommit: { onCommit(name) })
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { focused = true }
            .onExitCommand { onCancel() }
    }
}

/// Recursive disclosure row for a workspace / folder / file.
struct NodeRow: View {
    let node: NodeData
    @Binding var session: AppSession
    @Binding var selection: NodeData?
    /// Tree depth (0 = a workspace's top-level child) → drives indentation.
    var depth: Int = 0
    @AppStorage(PrefKeys.hideFileExtensions) private var hideFileExtensions: Bool = false
    @AppStorage(PrefKeys.sidebarSortMode) private var sortModeRaw = SidebarSortMode.name.rawValue

    /// Per-level indent. The workspace header sits flush-left (depth 0 ⇒ no
    /// indent); its children start one clear step in, so the hierarchy reads.
    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: CGFloat(depth) * 16, bottom: 0, trailing: 4)
    }

    /// Persisted expansion binding so the tree reopens the way it was left.
    private var expansion: Binding<Bool> {
        Binding(
            get: { session.isFolderExpanded(node.url, isWorkspace: node.isWorkspace) },
            set: { session.setFolderExpanded(node.url, isWorkspace: node.isWorkspace, $0) }
        )
    }

    var body: some View {
        if node.isWorkspace {
            // The workspace's own header row is rendered by SidebarView; here we
            // only emit its contents (one level in) when expanded.
            if expansion.wrappedValue {
                ForEach(filteredChildren(), id: \.self) { child in
                    NodeRow(node: child, session: $session, selection: $selection, depth: depth + 1)
                }
            }
        } else {
            // One uniform row + (for expanded folders) its children as sibling
            // rows. NO DisclosureGroup — its system indent gutter fought the
            // manual insets and made parents look more indented than children.
            // Indentation is purely depth · step, consistent for every row.
            rowView
            if node.isExpandable, expansion.wrappedValue {
                ForEach(filteredChildren(), id: \.self) { child in
                    NodeRow(node: child, session: $session, selection: $selection, depth: depth + 1)
                }
            }
        }
    }

    /// A single tree row: [indent][chevron|spacer][icon][name]. It is a NATIVE
    /// List row (tagged, not wrapped in a Button) so clicking it selects the row
    /// AND makes the List first responder — that's what lets arrow keys work and
    /// keeps focus in the sidebar. Opening the file happens from the selection
    /// change (ContentView), as a browse. Only the chevron is a button, so
    /// clicking it folds/unfolds without needing to consume the row's click.
    private var rowView: some View {
        HStack(spacing: 4) {
            if node.isExpandable {
                Button { expansion.wrappedValue.toggle() } label: {
                    Image(systemName: expansion.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 10)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 10)
            }
            Image(systemName: node.isExpandable ? "folder" : icon(for: node))
                .foregroundStyle(.secondary)
            label
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .listRowInsets(rowInsets)
        .tag(node)
        .contextMenu { menuItems }
    }

    /// Either the static row name, or — when this node is the inline-rename
    /// target — an editable NSTextField that commits on Return / blur and
    /// cancels on Esc.
    @ViewBuilder
    private var label: some View {
        if session.renamingNodeID == node.id {
            InlineRenameField(initial: node.name) { newName in
                session.renameNode(node, to: newName)
            } onCancel: {
                session.renamingNodeID = nil
            }
        } else {
            // Folders + workspaces always show their full name. Only file
            // rows are subject to the Hide Extensions toggle so directories
            // like `notes.archive` keep their identifying suffix.
            Text(node.isFile
                 ? SidebarLabel.displayName(node.name, hideExtensions: hideFileExtensions)
                 : node.name)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if node.isExpandable {
            // New File submenu — pre-pick extension so users don't get an
            // .md file when they meant .mmd, etc.
            Menu(L("sidebar.menu.new_file")) {
                Button(L("sidebar.menu.new_file.mindmap"))  { session.createFile(in: node, extension: "mmd") }
                Button(L("sidebar.menu.new_file.markdown")) { session.createFile(in: node, extension: "md") }
                Button(L("sidebar.menu.new_file.plantuml")) { session.createFile(in: node, extension: "puml") }
                Button(L("sidebar.menu.new_file.csv"))      { session.createFile(in: node, extension: "csv") }
                Button(L("sidebar.menu.new_file.text"))     { session.createFile(in: node, extension: "txt") }
            }
            Button(L("sidebar.menu.new_folder")) { session.createFolder(in: node) }
            Divider()
        }
        if node.isFile {
            Button(L("sidebar.menu.open_in_new_tab")) { session.open(url: node.url, inNewTab: true) }
            Divider()
        }
        Button(L("sidebar.menu.reveal_in_finder")) { session.revealInFinder(node) }
        if node.isFile {
            Button(L("sidebar.menu.open_in_default_app")) { session.openInDefaultApp(node) }
        }
        Button(L("sidebar.menu.open_terminal"))    { session.openTerminal(at: node) }
        Divider()
        Button(L("sidebar.menu.copy_path")) { session.copyPath(node, relative: false) }
        Button(L("sidebar.menu.copy_relative_path")) { session.copyPath(node, relative: true) }
        Divider()
        if !node.isWorkspace {
            Button(L("sidebar.menu.duplicate")) { session.duplicateNode(node) }
            Button(L("sidebar.menu.copy_file")) { session.copyFileToPasteboard(node) }
            Button(L("sidebar.menu.move_to")) { session.moveNodeToFolder(node) }
        }
        if node.isExpandable {
            Button(L("sidebar.menu.paste_file")) { session.pasteFile(into: node) }
        }
        if !node.isWorkspace {
            Button(L("sidebar.menu.rename")) { session.renameNode(node) }
            Button(L("sidebar.menu.delete"), role: .destructive) { session.deleteNode(node) }
            Button(L("sidebar.menu.delete_permanently"), role: .destructive) { session.deleteNodePermanently(node) }
        } else {
            Button(L("sidebar.menu.remove_workspace"), role: .destructive) { session.removeWorkspace(node) }
        }
    }

    private func icon(for node: NodeData) -> String {
        node.fileType?.sfSymbolName ?? SupportedFileType.unknownSymbolName
    }

    /// Apply the workspace's file-type filter to this folder's children.
    /// Folders always show through so the user can drill in even when
    /// nothing in the immediate folder matches.
    private func filteredChildren() -> [NodeData] {
        var raw = node.children(config: WorkspaceConfig.fromPreferences())
        let filter = session.sidebarTypeFilter
        if !filter.isEmpty {
            raw = raw.filter { child in
                if child.isExpandable { return true }
                guard let type = child.fileType else { return false }
                return filter.contains(type)
            }
        }
        let mode = SidebarSortMode(rawValue: sortModeRaw) ?? .name
        return SidebarSort.sorted(raw, mode: mode,
                                  recents: CollectionStore.shared.recents.map(\.url))
    }
}
