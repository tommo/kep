import Foundation

/// Shape used to draw the parent→child line in the mindmap canvas.
/// Persisted via `PrefKeys.mindmapConnectorStyle` (raw String value).
public enum ConnectorStyle: String, CaseIterable {
    case bezier
    case polyline

    /// Parse the pref string. Unknown / nil values fall back to `.bezier`
    /// to match historical behaviour.
    public static func from(rawString raw: String?) -> ConnectorStyle {
        guard let raw, let parsed = ConnectorStyle(rawValue: raw) else {
            return .bezier
        }
        return parsed
    }
}
