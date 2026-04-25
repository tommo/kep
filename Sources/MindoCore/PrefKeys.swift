import Foundation

/// Centralised UserDefaults key namespace shared between the Preferences UI
/// (in the Mindo executable) and downstream consumers in MindoBase /
/// MindoMindMap / MindoGenAI. Lives in MindoCore so every module can read
/// the same keys without dragging the app target into their dependency
/// graph.
public enum PrefKeys {
    public static let theme = "mindo.prefs.theme"
    public static let outlineOpenByDefault = "mindo.prefs.outlineOpenByDefault"
    public static let editorFontSize = "mindo.prefs.editorFontSize"
    public static let markdownPreviewSyncScroll = "mindo.prefs.markdownPreviewSyncScroll"
    public static let mindmapVerticalGap = "mindo.prefs.mindmapVerticalGap"
    public static let mindmapHorizontalGap = "mindo.prefs.mindmapHorizontalGap"
    public static let aiStreamingEnabled = "mindo.prefs.aiStreamingEnabled"

    /// Convenience: pulls a Double from UserDefaults, returning `fallback`
    /// when the key is unset or stored as a non-positive value.
    public static func double(_ key: String, fallback: Double) -> Double {
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : fallback
    }

    /// Pulls a Bool but treats "key not set yet" as `fallback` rather than
    /// always returning false.
    public static func bool(_ key: String, fallback: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }
}
