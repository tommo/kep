import SwiftUI
import MindoCore

/// Workspaces + lazy folder/file tree on the left of the window.
struct SidebarView: View {
    @Binding var session: AppSession
    @Binding var selection: NodeData?
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
                                Image(systemName: "folder.badge.gearshape")
                                Text(root.name).font(.headline)
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
                .environment(\.defaultMinListRowHeight, 18)
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
    @AppStorage(PrefKeys.hideFileExtensions) private var hideFileExtensions: Bool = false

    /// Persisted expansion binding so the tree reopens the way it was left.
    private var expansion: Binding<Bool> {
        Binding(
            get: { session.isFolderExpanded(node.url, isWorkspace: node.isWorkspace) },
            set: { session.setFolderExpanded(node.url, isWorkspace: node.isWorkspace, $0) }
        )
    }

    var body: some View {
        if node.isExpandable {
            DisclosureGroup(isExpanded: expansion) {
                ForEach(filteredChildren(), id: \.self) { child in
                    NodeRow(node: child, session: $session, selection: $selection)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: node.isWorkspace ? "shippingbox" : "folder")
                    label
                }
                .font(.system(size: 12))
                .tag(node)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                .contextMenu { menuItems }
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: icon(for: node))
                    .foregroundStyle(.secondary)
                label
                Spacer(minLength: 0)
                if isRecent {
                    // Subtle accent dot for recently-opened files —
                    // helps the user spot what they were last editing.
                    Circle()
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: 5, height: 5)
                        .help(L("sidebar.recently_opened"))
                }
            }
            .font(.system(size: 12))
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            // Always-visible highlight for the file that's open in the editor.
            // SwiftUI's List hides its built-in selection when it isn't the
            // focused responder — and opening a file moves focus to the editor,
            // so the row "deselected". A row background tied to the active
            // document survives focus loss (Finder / VS Code behaviour). nil
            // keeps the default so keyboard-nav selection still shows.
            .listRowBackground(isActiveDocument ? Color.accentColor.opacity(0.20) : nil)
            .tag(node)
            .contextMenu { menuItems }
        }
    }

    /// True when this file is the document currently shown in the editor.
    /// Drives an always-visible row highlight (see listRowBackground) so the
    /// open file stays marked even when the sidebar isn't focused.
    private var isActiveDocument: Bool {
        guard node.isFile, let active = session.activeDocument?.fileURL else { return false }
        return active.standardizedFileURL == node.url.standardizedFileURL
    }

    /// True when this node's URL is in the workspace's recents list.
    /// Folders never qualify (they're not "opened" in the doc sense).
    private var isRecent: Bool {
        guard node.isFile else { return false }
        let recentPaths = Set(CollectionStore.shared.recents.map { $0.path })
        return recentPaths.contains(node.url.path)
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
        let raw = node.children(config: WorkspaceConfig.fromPreferences())
        let filter = session.sidebarTypeFilter
        guard !filter.isEmpty else { return raw }
        return raw.filter { child in
            if child.isExpandable { return true }
            guard let type = child.fileType else { return false }
            return filter.contains(type)
        }
    }
}
