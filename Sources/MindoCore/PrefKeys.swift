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
    /// Show a confirmation alert before quitting the app. Default off
    /// (matches the macOS expectation). Mirrors mindolph's
    /// `GENERAL_CONFIRM_BEFORE_QUITTING`.
    public static let confirmBeforeQuit = "mindo.prefs.confirmBeforeQuit"
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
    /// Show a faint dotted grid behind the mindmap canvas. Default off.
    /// Mirrors mindolph's MmdPreferencesPane `ckbShowGrid`.
    public static let mindmapShowGrid = "mindo.prefs.mindmapShowGrid"
    /// Spacing in points between grid lines. Mirrors `spnGridStep`.
    /// Default 16pt — visible without crowding most reasonable zoom
    /// levels.
    public static let mindmapGridStep = "mindo.prefs.mindmapGridStep"
    /// Render a drop shadow under non-root topic boxes. Default on
    /// (matches mindolph's default + Mindo's existing behavior).
    /// Mirrors `ckbDropShadow` in MmdPreferencesPane.
    public static let mindmapDropShadow = "mindo.prefs.mindmapDropShadow"
    /// When the user drops a topic onto a collapsed parent, auto-clear
    /// the parent's `collapsed` attribute so the dropped subtree is
    /// visible. Default on. Mirrors `ckbUnfoldCollapsedDropTarget`.
    public static let mindmapUnfoldCollapsedDropTarget = "mindo.prefs.mindmapUnfoldCollapsedDropTarget"
    /// On canvas paste, parse the pasteboard's plain text as an
    /// indented outline and graft the resulting subtree under the
    /// selection. Default on. Mirrors `ckbSmartTextPaste`.
    public static let mindmapSmartTextPaste = "mindo.prefs.mindmapSmartTextPaste"
    /// Override for the topic rectangle corner radius (points). 0 or
    /// unset = use the theme's value. Mirrors `spnRoundRadius`.
    public static let mindmapCornerRadius = "mindo.prefs.mindmapCornerRadius"
    /// Topic border stroke width in points. Default 1.0pt (matches
    /// previous behavior). Mirrors `spnBorderWidth`.
    public static let mindmapBorderWidth = "mindo.prefs.mindmapBorderWidth"
    /// Optional path to a `dot` binary (Graphviz). When set, mindo
    /// passes it to PlantUML via the GRAPHVIZ_DOT env var so non-
    /// standard Homebrew prefixes / Nix profiles / portable installs
    /// still resolve. Mirrors mindolph's `plantuml.dotpath`.
    public static let plantumlGraphvizPath = "mindo.prefs.plantumlGraphvizPath"

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
