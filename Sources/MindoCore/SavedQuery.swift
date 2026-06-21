import Foundation

/// A reusable named property/text query (the "saved view" of #203 / roadmap T4).
/// Stored globally (queries like `priority:1 #urgent` are map-agnostic), as JSON
/// under `PrefKeys.savedQueries`.
public struct SavedQuery: Codable, Identifiable, Equatable, Sendable {
    public var name: String
    public var query: String
    public var id: String { name }

    public init(name: String, query: String) {
        self.name = name
        self.query = query
    }
}

/// Pure JSON (de)serialization for the saved-query list, so persistence is
/// unit-testable without touching UserDefaults.
public enum SavedQueriesCodec {
    public static func encode(_ queries: [SavedQuery]) -> Data {
        (try? JSONEncoder().encode(queries)) ?? Data()
    }

    public static func decode(_ data: Data?) -> [SavedQuery] {
        guard let data, let list = try? JSONDecoder().decode([SavedQuery].self, from: data) else { return [] }
        return list
    }

    /// Insert/replace `query` by name (case-sensitive), keeping the list unique
    /// by name. A new entry is appended; an existing name is updated in place.
    public static func upserting(_ query: SavedQuery, into list: [SavedQuery]) -> [SavedQuery] {
        var out = list
        if let i = out.firstIndex(where: { $0.name == query.name }) { out[i] = query }
        else { out.append(query) }
        return out
    }
}
