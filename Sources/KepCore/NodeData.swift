import Foundation

/// Type of a tree node in the workspace sidebar. Mirrors `NodeType`.
public enum NodeType: String, Sendable {
    case workspace
    case folder
    case file
    case unknown
}

/// Tree node representing a workspace, folder, or file in the sidebar.
/// Mirrors `NodeData` from `mindolph-core/model`.
public final class NodeData: Identifiable {
    public let id = UUID()
    public var nodeType: NodeType
    public var url: URL
    public var name: String
    public weak var workspace: NodeData?
    public weak var parent: NodeData?

    private var loaded: Bool = false
    private var _children: [NodeData] = []

    public init(workspace name: String, url: URL) {
        self.nodeType = .workspace
        self.name = name
        self.url = url
    }

    public init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.nodeType = isDir.boolValue ? .folder : .file
    }

    public init(nodeType: NodeType, url: URL) {
        self.nodeType = nodeType
        self.url = url
        self.name = url.lastPathComponent
    }

    public var isWorkspace: Bool { nodeType == .workspace }
    public var isFolder: Bool { nodeType == .folder }
    public var isFile: Bool { nodeType == .file }

    /// True when this node represents a container that can be expanded to show children.
    public var isExpandable: Bool { isWorkspace || isFolder }

    public var fileType: SupportedFileType? {
        guard isFile else { return nil }
        return SupportedFileType.classify(url: url)
    }

    /// File-relative path from the owning workspace, when one is set.
    public var workspaceRelativePath: String {
        guard let ws = workspace else { return url.lastPathComponent }
        let base = ws.url.path
        let p = url.path
        guard p.hasPrefix(base) else { return p }
        return String(p.dropFirst(base.count + 1))
    }

    /// Lazy children — evaluated on first access. Folders are listed before files,
    /// each alphabetically.
    public func children(config: WorkspaceConfig = .default) -> [NodeData] {
        if loaded { return _children }
        loadChildren(config: config)
        return _children
    }

    public func reloadChildren(config: WorkspaceConfig = .default) {
        loaded = false
        loadChildren(config: config)
    }

    private func loadChildren(config: WorkspaceConfig) {
        loaded = true
        guard isExpandable else { _children = []; return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { _children = []; return }

        let owningWorkspace = self.workspace ?? (self.isWorkspace ? self : nil)
        func makeChild(url: URL, type: NodeType) -> NodeData {
            let n = NodeData(nodeType: type, url: url)
            n.workspace = owningWorkspace
            n.parent = self
            return n
        }

        var folders: [NodeData] = []
        var files: [NodeData] = []
        for child in contents {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &isDir)
            if isDir.boolValue {
                guard config.acceptsDirectory(child) else { continue }
                folders.append(makeChild(url: child, type: .folder))
            } else {
                guard config.acceptsFile(child) else { continue }
                files.append(makeChild(url: child, type: .file))
            }
        }
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        _children = folders + files
    }
}

// Identity is by standardized file URL, NOT object identity. The sidebar tree
// rebuilds NodeData instances whenever a workspace reloads (e.g. an FSEvents
// burst fired by opening a file), so an instance-based identity would silently
// drop the List selection on every reload — the node "moves" to a fresh object
// the selection binding no longer matches. A filesystem path uniquely names a
// node, so URL identity is both correct and what callers (findNode dedupe,
// the watcher comment) already assume.
extension NodeData: Equatable {
    public static func == (lhs: NodeData, rhs: NodeData) -> Bool {
        lhs.url.standardizedFileURL == rhs.url.standardizedFileURL
    }
}

extension NodeData: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(url.standardizedFileURL)
    }
}
