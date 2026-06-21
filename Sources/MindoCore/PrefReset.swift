import Foundation

/// Groups the preference keys by the Settings tab that owns them, and resets
/// a group by removing its keys so the `@AppStorage`-backed controls snap
/// back to their declared defaults. The grouping is pure data so a test can
/// assert the groups stay disjoint and keep covering every settable key —
/// the thing that silently rots when a new pref is added but not wired into
/// "Restore Defaults".
public enum PrefResetGroup: String, CaseIterable, Sendable {
    case general
    case editor
    case mindmap
    case ai

    /// The keys this tab's "Restore Defaults" button clears.
    public var keys: [String] {
        switch self {
        case .general:
            return [
                PrefKeys.theme,
                PrefKeys.appAppearance,
                PrefKeys.outlineOpenByDefault,
                PrefKeys.showHiddenFiles,
                PrefKeys.hideFileExtensions,
                PrefKeys.confirmBeforeQuit,
                PrefKeys.openLastFiles,
                PrefKeys.sidebarVisible,
            ]
        case .editor:
            return [
                PrefKeys.editorFontSize,
                PrefKeys.editorFontFamily,
                PrefKeys.markdownPreviewSyncScroll,
                PrefKeys.markdownPreviewFont,
                PrefKeys.markdownPreviewMonoFont,
                PrefKeys.autosaveOnBlur,
                PrefKeys.markdownSplitVertical,
                PrefKeys.markdownViewMode,
                PrefKeys.plantumlSplitVertical,
                PrefKeys.plantumlGraphvizPath,
                PrefKeys.editorTheme,
            ]
        case .mindmap:
            return [
                PrefKeys.mindmapVerticalGap,
                PrefKeys.mindmapHorizontalGap,
                PrefKeys.mindmapConnectorStyle,
                PrefKeys.mindmapConnectorWidth,
                PrefKeys.mindmapInheritFillColor,
                PrefKeys.mindmapTrimTopicText,
                PrefKeys.mindmapShowGrid,
                PrefKeys.mindmapGridStep,
                PrefKeys.mindmapDropShadow,
                PrefKeys.mindmapUnfoldCollapsedDropTarget,
                PrefKeys.mindmapSmartTextPaste,
                PrefKeys.mindmapCornerRadius,
                PrefKeys.mindmapBorderWidth,
            ]
        case .ai:
            return [PrefKeys.aiStreamingEnabled]
        }
    }
}

public enum PrefReset {
    /// Remove every key in `group` from `defaults`, so the matching
    /// `@AppStorage` properties revert to the defaults declared at their
    /// use sites.
    public static func reset(_ group: PrefResetGroup, in defaults: UserDefaults = .standard) {
        for key in group.keys { defaults.removeObject(forKey: key) }
    }
}
