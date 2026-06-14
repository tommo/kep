import Foundation

/// Serialize the sidebar's per-folder expansion state (a path→isExpanded
/// map of the folders the user has explicitly toggled) to and from a stored
/// string, so the tree reopens the way it was left. Pure JSON round-trip,
/// kept out of the view so it's unit-testable. Untoggled folders aren't in
/// the map and fall back to a caller-supplied default (workspaces open,
/// folders closed).
public enum SidebarExpansionState {

    /// Encode the map to a compact, stable JSON object string.
    public static func encode(_ map: [String: Bool]) -> String {
        guard !map.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    /// Decode a stored string back to the map. Tolerates nil/empty/garbage by
    /// returning an empty map (everything falls back to its default).
    public static func decode(_ raw: String?) -> [String: Bool] {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let map = obj as? [String: Bool] else { return [:] }
        return map
    }

    /// Whether `path` should render expanded, given the user-toggled `map`
    /// and the `defaultExpanded` for untouched folders.
    public static func isExpanded(_ path: String, in map: [String: Bool], defaultExpanded: Bool) -> Bool {
        map[path] ?? defaultExpanded
    }
}
