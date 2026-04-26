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
    /// Show dotfiles + hidden directories in the workspace sidebar.
    /// Default false — matches Finder. Mirrors mindolph's
    /// `GENERAL_SHOW_HIDDEN_FILES`.
    public static let showHiddenFiles = "mindo.prefs.showHiddenFiles"
    /// Strip the trailing extension from file rows in the workspace
    /// sidebar (e.g. `notes.mmd` → `notes`). Folders + workspaces are
    /// untouched. Mirrors mindolph's `GENERAL_HIDE_EXTENSION`.
    public static let hideFileExtensions = "mindo.prefs.hideFileExtensions"
    /// Optional preferred monospaced font family for the markdown /
    /// plantuml editors. Empty = use the system default monospaced font.
    public static let editorFontFamily = "mindo.prefs.editorFontFamily"
    /// Markdown editor split orientation. true (default) = source on
    /// the left, preview on the right; false = source on top, preview
    /// below. Mirrors mindolph's per-editor Orientation pref.
    public static let markdownSplitVertical = "mindo.prefs.markdownSplitVertical"
    /// PlantUML editor split orientation — same semantics as
    /// `markdownSplitVertical` but for the puml editor's source/preview
    /// pane.
    public static let plantumlSplitVertical = "mindo.prefs.plantumlSplitVertical"
    public static let markdownPreviewSyncScroll = "mindo.prefs.markdownPreviewSyncScroll"
    public static let mindmapVerticalGap = "mindo.prefs.mindmapVerticalGap"
    public static let mindmapHorizontalGap = "mindo.prefs.mindmapHorizontalGap"
    public static let aiStreamingEnabled = "mindo.prefs.aiStreamingEnabled"
    public static let autosaveOnBlur = "mindo.prefs.autosaveOnBlur"
    public static let showJumpArrows = "mindo.prefs.showJumpArrows"
    public static let mindmapConnectorStyle = "mindo.prefs.mindmapConnectorStyle"
    public static let mindmapConnectorWidth = "mindo.prefs.mindmapConnectorWidth"
    public static let mindmapInheritFillColor = "mindo.prefs.mindmapInheritFillColor"
    public static let mindmapTrimTopicText = "mindo.prefs.mindmapTrimTopicText"

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

    /// Pulls a String, returning nil when the key is unset or stored as
    /// an empty string. Useful for "system default" semantics where
    /// any value at all means override.
    public static func string(_ key: String) -> String? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
