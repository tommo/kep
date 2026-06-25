import Foundation
import Logging

/// Singleton for loading/saving the user's workspace list and building
/// `NodeData` trees on demand. Mirrors `WorkspaceManager` from `mindolph-core`.
public final class WorkspaceManager {
    public static let shared = WorkspaceManager()

    private let logger = Logger(label: "kep.core.workspace")
    private let workspaceListURL: URL
    public private(set) var list: WorkspaceList

    public init(directory: URL = KepCore.applicationSupportURL) {
        self.workspaceListURL = directory.appendingPathComponent("workspaces.json")
        self.list = JSONFile.read(WorkspaceList.self, from: workspaceListURL) ?? WorkspaceList()
    }

    public func save() throws {
        try JSONFile.write(list, to: workspaceListURL)
    }

    public func add(workspaceAt url: URL) -> WorkspaceMeta {
        let meta = WorkspaceMeta(url: url)
        list.add(meta)
        try? save()
        return meta
    }

    public func remove(_ meta: WorkspaceMeta) {
        list.remove(meta)
        try? save()
    }

    /// Set (or clear, with nil/empty) the display alias for the workspace at
    /// `url`, then persist. Returns the updated meta if found.
    @discardableResult
    public func setAlias(_ alias: String?, forWorkspaceAt url: URL) -> WorkspaceMeta? {
        guard let idx = list.projects.firstIndex(where: { $0.url == url }) else { return nil }
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        list.projects[idx].alias = (trimmed?.isEmpty == false) ? trimmed : nil
        try? save()
        return list.projects[idx]
    }

    /// Drop entries whose folder no longer exists on disk and persist.
    public func removeNonExistentWorkspaces() {
        list.removeNonExistent()
        try? save()
    }

    /// Replace the workspace ordering with `newOrder`, then persist. Used by
    /// the sidebar drag-to-reorder. Caller is responsible for ensuring
    /// `newOrder` is a permutation of the current list (no adds/removes).
    public func reorder(_ newOrder: [WorkspaceMeta]) {
        list.projects = newOrder
        try? save()
    }

    /// Build a `NodeData` workspace root for the given meta. Children load lazily.
    public func loadTree(for meta: WorkspaceMeta) -> NodeData {
        let node = NodeData(workspace: meta.name, url: meta.url)
        node.workspace = node
        return node
    }

}
