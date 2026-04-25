import Foundation
import Logging

/// Singleton for loading/saving the user's workspace list and building
/// `NodeData` trees on demand. Mirrors `WorkspaceManager` from `mindolph-core`.
public final class WorkspaceManager {
    public static let shared = WorkspaceManager()

    private let logger = Logger(label: "mindo.core.workspace")
    private let workspaceListURL: URL
    public private(set) var list: WorkspaceList

    public init(directory: URL = MindoCore.applicationSupportURL) {
        self.workspaceListURL = directory.appendingPathComponent("workspaces.json")
        self.list = Self.loadList(from: workspaceListURL) ?? WorkspaceList()
    }

    public func save() throws {
        let dir = workspaceListURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(list)
        try data.write(to: workspaceListURL, options: .atomic)
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

    /// Drop entries whose folder no longer exists on disk and persist.
    public func removeNonExistentWorkspaces() {
        list.removeNonExistent()
        try? save()
    }

    /// Build a `NodeData` workspace root for the given meta. Children load lazily.
    public func loadTree(for meta: WorkspaceMeta) -> NodeData {
        let node = NodeData(workspace: meta.name, url: meta.url)
        node.workspace = node
        return node
    }

    private static func loadList(from url: URL) -> WorkspaceList? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkspaceList.self, from: data)
    }
}
