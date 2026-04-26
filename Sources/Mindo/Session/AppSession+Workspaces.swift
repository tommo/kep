import AppKit
import MindoCore

extension AppSession {

    func openWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addWorkspace(url: url)
    }

    func addWorkspace(url: URL) {
        let mgr = WorkspaceManager.shared
        let meta = mgr.add(workspaceAt: url)
        workspaces = mgr.list.projects
        if !workspaceRoots.contains(where: { $0.url == url }) {
            let node = mgr.loadTree(for: meta)
            workspaceRoots.append(node)
            startWorkspaceWatcher(for: node)
        }
    }

    func removeWorkspace(_ root: NodeData) {
        let mgr = WorkspaceManager.shared
        let meta = WorkspaceMeta(url: root.url)
        mgr.remove(meta)
        workspaces = mgr.list.projects
        workspaceRoots.removeAll { $0.url == root.url }
        stopWorkspaceWatcher(for: root.url)
    }

    /// Move a workspace from `sourcePath` to `targetPath`'s slot in the
    /// sidebar. Standard macOS reorder semantics — source lands at target's
    /// original index, target shifts away in the drag direction. Persists
    /// via WorkspaceManager.reorder.
    func reorderWorkspace(from sourcePath: String, to targetPath: String) {
        let paths = workspaceRoots.map { $0.url.path }
        let reorderedPaths = TabReorder.move(paths, from: sourcePath, to: targetPath)
        guard reorderedPaths != paths else { return }
        let pathToRoot = Dictionary(uniqueKeysWithValues: workspaceRoots.map { ($0.url.path, $0) })
        workspaceRoots = reorderedPaths.compactMap { pathToRoot[$0] }
        let pathToMeta = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.url.path, $0) })
        let newOrder = reorderedPaths.compactMap { pathToMeta[$0] }
        workspaces = newOrder
        WorkspaceManager.shared.reorder(newOrder)
    }

    /// Install the FSEvents watcher for a workspace's root tree. Called from
    /// init for the existing workspaces and from addWorkspace for new ones.
    func startWorkspaceWatcher(for node: NodeData) {
        guard workspaceWatchers[node.url] == nil else { return }
        let watcher = WorkspaceWatcher(url: node.url) { [weak self, weak node] _ in
            guard let self, let node else { return }
            // FSEvents fires bursts; coalesced 500ms inside the watcher.
            // We refresh from root because per-path delta would require
            // mapping changed paths to NodeData instances; the tree's
            // lazy children + identity-by-URL keeps this cheap.
            node.reloadChildren()
            // Trigger the @Observable to re-publish.
            self.workspaceRoots = self.workspaceRoots
        }
        watcher.start()
        workspaceWatchers[node.url] = watcher
    }

    func stopWorkspaceWatcher(for url: URL) {
        workspaceWatchers[url]?.stop()
        workspaceWatchers.removeValue(forKey: url)
    }
}
