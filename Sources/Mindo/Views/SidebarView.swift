import SwiftUI
import MindoCore

/// Workspaces + lazy folder/file tree on the left of the window.
struct SidebarView: View {
    @Binding var session: AppSession
    @Binding var selection: NodeData?

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
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

/// Recursive disclosure row for a workspace / folder / file.
struct NodeRow: View {
    let node: NodeData
    @Binding var session: AppSession
    @Binding var selection: NodeData?

    var body: some View {
        if node.isExpandable {
            DisclosureGroup {
                ForEach(node.children(), id: \.self) { child in
                    NodeRow(node: child, session: $session, selection: $selection)
                }
            } label: {
                HStack {
                    Image(systemName: node.isWorkspace ? "shippingbox" : "folder")
                    Text(node.name)
                }
                .tag(node)
                .contextMenu { menuItems }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: icon(for: node))
                    .foregroundStyle(.secondary)
                Text(node.name)
            }
            .tag(node)
            .contextMenu { menuItems }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if node.isExpandable {
            Button(L("sidebar.menu.new_file"))   { session.createFile(in: node) }
            Button(L("sidebar.menu.new_folder")) { session.createFolder(in: node) }
            Divider()
        }
        Button(L("sidebar.menu.reveal_in_finder")) { session.revealInFinder(node) }
        Button(L("sidebar.menu.open_terminal"))    { session.openTerminal(at: node) }
        Divider()
        if !node.isWorkspace {
            Button(L("sidebar.menu.rename")) { session.renameNode(node) }
            Button(L("sidebar.menu.delete"), role: .destructive) { session.deleteNode(node) }
        } else {
            Button(L("sidebar.menu.remove_workspace"), role: .destructive) { session.removeWorkspace(node) }
        }
    }

    private func icon(for node: NodeData) -> String {
        node.fileType?.sfSymbolName ?? SupportedFileType.unknownSymbolName
    }
}
