import Foundation

/// Persisted reference to a workspace root on disk. Mirrors `WorkspaceMeta`.
public struct WorkspaceMeta: Codable, Hashable, Sendable {
    public var baseDirPath: String

    public init(baseDirPath: String) {
        self.baseDirPath = baseDirPath
    }

    public init(url: URL) {
        self.baseDirPath = url.path
    }

    public var url: URL { URL(fileURLWithPath: baseDirPath) }

    public var name: String {
        URL(fileURLWithPath: baseDirPath).lastPathComponent
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: baseDirPath)
    }

    public func contains(_ url: URL) -> Bool {
        let p = url.path
        return p == baseDirPath || p.hasPrefix(baseDirPath + "/")
    }
}

/// Codable container for the user's known workspaces. Mirrors `WorkspaceList`.
/// JSON is persisted in `~/Library/Application Support/Mindo/workspaces.json`.
public struct WorkspaceList: Codable, Sendable {
    /// Field name `projects` matches the Java original for forward-compat with imported configs.
    public var projects: [WorkspaceMeta]

    public init(projects: [WorkspaceMeta] = []) {
        // Preserve order, drop dupes.
        var seen = Set<String>()
        self.projects = projects.filter { seen.insert($0.baseDirPath).inserted }
    }

    public mutating func add(_ workspace: WorkspaceMeta) {
        if !projects.contains(workspace) { projects.append(workspace) }
    }

    public mutating func remove(_ workspace: WorkspaceMeta) {
        projects.removeAll { $0 == workspace }
    }

    public mutating func removeNonExistent() {
        projects.removeAll { !$0.exists }
    }

    /// Return the deepest matching workspace (since a sub-dir can be itself a workspace).
    public func match(filePath: String) -> WorkspaceMeta? {
        projects
            .filter { filePath.hasPrefix($0.baseDirPath) }
            .max(by: { $0.baseDirPath.count < $1.baseDirPath.count })
    }
}

/// Configuration for filtering files shown in the workspace tree. Mirrors `WorkspaceConfig`.
public struct WorkspaceConfig: Sendable {
    public var includeSuffixes: [String]?
    public var excludeSuffixes: [String]
    public var showHiddenFiles: Bool
    public var showHiddenDirectories: Bool

    public init(
        includeSuffixes: [String]? = nil,
        excludeSuffixes: [String] = [".DS_Store"],
        showHiddenFiles: Bool = false,
        showHiddenDirectories: Bool = false
    ) {
        self.includeSuffixes = includeSuffixes
        self.excludeSuffixes = excludeSuffixes
        self.showHiddenFiles = showHiddenFiles
        self.showHiddenDirectories = showHiddenDirectories
    }

    public static let `default` = WorkspaceConfig()

    public func acceptsFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if !showHiddenFiles && name.hasPrefix(".") { return false }
        let lower = name.lowercased()
        for ex in excludeSuffixes where lower.hasSuffix(ex.lowercased()) { return false }
        if let inc = includeSuffixes, !inc.isEmpty {
            return inc.contains { lower.hasSuffix($0.lowercased()) }
        }
        return true
    }

    public func acceptsDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if !showHiddenDirectories && name.hasPrefix(".") { return false }
        return true
    }
}
