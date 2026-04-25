import Foundation

/// Tiny helper for the per-document JSON files that Mindo persists in
/// `~/Library/Application Support/Mindo/` (workspaces, collections, recents,
/// snippets, llm_config). Every store had its own bespoke load+save dance —
/// this just centralises the create-parent-dir + atomic write recipe.
public enum JSONFile {

    /// Decode `T` from `url`. Returns nil for "missing file" and "corrupt
    /// JSON" alike — caller substitutes a fresh empty value.
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// JSON-encode `value` and atomically write to `url`, creating any
    /// missing parent directories first.
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }
}
