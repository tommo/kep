import Foundation

/// One indexed file inside a workspace — what the quick switcher lists.
public struct WorkspaceFile: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public let url: URL
    /// Workspace display name this file belongs to (for the secondary line).
    public let workspaceName: String
    /// Path relative to the owning workspace root, e.g. `notes/todo.md`.
    public let relativePath: String

    public var name: String { url.lastPathComponent }

    public init(url: URL, workspaceName: String, relativePath: String) {
        self.url = url
        self.workspaceName = workspaceName
        self.relativePath = relativePath
    }
}

/// Flat, on-demand index of every file under the open workspace roots —
/// the data source for an Obsidian-style ⌘O quick switcher. Walks the
/// filesystem directly (rather than the lazy sidebar `NodeData` tree) so
/// indexing never mutates sidebar state and stays unit-testable against a
/// temp directory.
public enum WorkspaceFileIndex {

    /// Walk `roots` depth-first, returning every accepted file. `config`
    /// gates which files/folders are visited (hidden-file rules, exclude
    /// suffixes), matching what the sidebar shows. `maxFiles` caps the
    /// result so a pathologically large workspace can't stall the UI; the
    /// walk stops early once the cap is hit.
    public static func index(
        roots: [(url: URL, name: String)],
        config: WorkspaceConfig = .fromPreferences(),
        maxFiles: Int = 20_000
    ) -> [WorkspaceFile] {
        var out: [WorkspaceFile] = []
        let fm = FileManager.default
        for root in roots {
            walk(root.url, base: root.url, workspaceName: root.name,
                 config: config, fm: fm, maxFiles: maxFiles, into: &out)
            if out.count >= maxFiles { break }
        }
        return out
    }

    private static func walk(
        _ dir: URL,
        base: URL,
        workspaceName: String,
        config: WorkspaceConfig,
        fm: FileManager,
        maxFiles: Int,
        into out: inout [WorkspaceFile]
    ) {
        guard out.count < maxFiles else { return }
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return }

        // Folders first, then files — both alphabetical — so the index
        // order is deterministic and mirrors the sidebar's ordering, which
        // becomes the stable tie-break when fuzzy scores are equal.
        var folders: [URL] = []
        var files: [URL] = []
        for child in contents {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: child.path, isDirectory: &isDir)
            if isDir.boolValue {
                if config.acceptsDirectory(child) { folders.append(child) }
            } else if config.acceptsFile(child) {
                files.append(child)
            }
        }
        folders.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        files.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for file in files {
            guard out.count < maxFiles else { return }
            out.append(WorkspaceFile(
                url: file,
                workspaceName: workspaceName,
                relativePath: relativePath(of: file, under: base)
            ))
        }
        for folder in folders {
            guard out.count < maxFiles else { return }
            walk(folder, base: base, workspaceName: workspaceName,
                 config: config, fm: fm, maxFiles: maxFiles, into: &out)
        }
    }

    /// Path of `url` relative to `base`, falling back to the last path
    /// component when `url` is not actually under `base`.
    static func relativePath(of url: URL, under base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath) else { return url.lastPathComponent }
        let trimmed = path.dropFirst(basePath.count)
        return String(trimmed.drop(while: { $0 == "/" }))
    }
}
