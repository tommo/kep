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
                    ForEach(session.workspaceRoots, id: \.self) { root in
                        Section {
                            NodeRow(node: root, session: $session, selection: $selection)
                        } header: {
                            HStack {
                                // Click the name (or chevron) to fold/unfold the
                                // whole workspace.
                                Button {
                                    let cur = session.isFolderExpanded(root.url, isWorkspace: true)
                                    session.setFolderExpanded(root.url, isWorkspace: true, !cur)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: session.isFolderExpanded(root.url, isWorkspace: true)
                                              ? "chevron.down" : "chevron.right")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        // Distinct vault glyph + accent tint so a
                                        // workspace never reads as a plain folder.
                                        Image(systemName: "books.vertical.fill")
                                            .foregroundStyle(Color.accentColor)
                                        Text(root.name).font(.headline)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(L("sidebar.tooltip.toggle_workspace"))
                                Spacer()
                                Button {
                                    session.removeWorkspace(root)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .help(L("sidebar.tooltip.remove_workspace"))
                            }
                            .onDrag { NSItemProvider(object: root.url.path as NSString) }
                            .onDrop(of: [.text], delegate: WorkspaceDropDelegate(
                                target: root.url.path,
                                session: $session
                            ))
                        }
                    }
                }
                .listStyle(.sidebar)
                .environment(\.defaultMinListRowHeight, 15)
                .controlSize(.small)
                // Arrow keys move the highlight only — flag the source so the
                // open-on-selection wiring skips them (#21). `.ignored` lets
                // the List perform its own arrow navigation afterwards.
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { _ in
                    onSelectionSource(.keyboardNavigation)
                    return .ignored
                }
                // Return opens the highlighted file (R6).
                .onKeyPress(.return) {
                    onConfirm()
                    return .handled
                }
            }
        }
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

    /// Per-level indent. Leading inset = base + depth · step.
    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 4 + CGFloat(depth) * 14, bottom: 0, trailing: 4)
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
            // The Section header shows the workspace and toggles its expansion;
            // list its contents directly (Obsidian-style) when expanded, rather
            // than repeating the workspace as a second root row.
            if expansion.wrappedValue {
                ForEach(filteredChildren(), id: \.self) { child in
                    NodeRow(node: child, session: $session, selection: $selection, depth: 0)
                }
            }
        } else if node.isExpandable {
            DisclosureGroup(isExpanded: expansion) {
                ForEach(filteredChildren(), id: \.self) { child in
                    NodeRow(node: child, session: $session, selection: $selection, depth: depth + 1)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    label
                }
                .font(.system(size: 12))
                .tag(node)
                .listRowInsets(rowInsets)
                .contextMenu { menuItems }
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: icon(for: node))
                    .foregroundStyle(.secondary)
                label
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .listRowInsets(rowInsets)
            .tag(node)
            .contextMenu { menuItems }
        }
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
