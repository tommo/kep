import Foundation

/// A named group of file URLs the user can re-open as a tab set. Mirrors
/// Mindolph's "Collection" feature.
public struct FileCollection: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var filePaths: [String]
    public var createdAt: Date

    public init(
        id: UUID = UUID(), name: String, filePaths: [String], createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.filePaths = filePaths
        self.createdAt = createdAt
    }

    public var fileURLs: [URL] {
        filePaths.map { URL(fileURLWithPath: $0) }
    }
}

/// Tracks a recent file open. Capped to a fixed window inside `RecentFilesStore`.
public struct RecentFileEntry: Codable, Hashable, Sendable {
    public var path: String
    public var openedAt: Date

    public init(path: String, openedAt: Date = Date()) {
        self.path = path
        self.openedAt = openedAt
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

/// JSON-persisted store for both Collections and Recent Files. Stored at
/// `~/Library/Application Support/Mindo/collections.json` and
/// `recent_files.json`.
public final class CollectionStore {
    public static let shared = CollectionStore()

    public private(set) var collections: [FileCollection]
    public private(set) var recents: [RecentFileEntry]
    public let recentLimit: Int

    private let collectionsURL: URL
    private let recentsURL: URL

    public init(directory: URL = MindoCore.applicationSupportURL, recentLimit: Int = 12) {
        self.collectionsURL = directory.appendingPathComponent("collections.json")
        self.recentsURL = directory.appendingPathComponent("recent_files.json")
        self.recentLimit = recentLimit

        if let data = try? Data(contentsOf: collectionsURL),
           let decoded = try? JSONDecoder().decode([FileCollection].self, from: data) {
            self.collections = decoded
        } else {
            self.collections = []
        }
        if let data = try? Data(contentsOf: recentsURL),
           let decoded = try? JSONDecoder().decode([RecentFileEntry].self, from: data) {
            self.recents = decoded
        } else {
            self.recents = []
        }
    }

    // MARK: - Collections

    public func addCollection(name: String, fileURLs: [URL]) -> FileCollection {
        let collection = FileCollection(name: name, filePaths: fileURLs.map(\.path))
        collections.removeAll { $0.name == name }   // de-dupe by name
        collections.append(collection)
        try? saveCollections()
        return collection
    }

    public func remove(collectionID: UUID) {
        collections.removeAll { $0.id == collectionID }
        try? saveCollections()
    }

    public func rename(collectionID: UUID, to newName: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[idx].name = newName
        try? saveCollections()
    }

    private func saveCollections() throws {
        let dir = collectionsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(collections)
        try data.write(to: collectionsURL, options: .atomic)
    }

    // MARK: - Recent files

    /// Bumps `url` to the front of the recents list (deduping by path), then
    /// trims to `recentLimit` entries.
    public func touch(url: URL) {
        let path = url.path
        recents.removeAll { $0.path == path }
        recents.insert(RecentFileEntry(path: path), at: 0)
        if recents.count > recentLimit {
            recents = Array(recents.prefix(recentLimit))
        }
        try? saveRecents()
    }

    public func clearRecents() {
        recents.removeAll()
        try? saveRecents()
    }

    private func saveRecents() throws {
        let dir = recentsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(recents)
        try data.write(to: recentsURL, options: .atomic)
    }
}
