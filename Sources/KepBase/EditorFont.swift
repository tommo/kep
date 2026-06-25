import AppKit
import KepCore

public extension Notification.Name {
    /// Posted by the Editor preferences pane when the editor or preview font
    /// (family/size) changes, so open markdown / PlantUML editors re-apply it
    /// live instead of only on the next document open. Mirrors
    /// `.csvFontChanged` / `.editorThemeChanged`. See feedback_settings_reapply_live.
    static let editorFontChanged = Notification.Name("kep.editorFontChanged")
}

/// Resolve the monospaced font the markdown / plantuml editors should
/// render with. Centralized so the lookup logic + fallback chain is
/// unit-testable without instantiating a textview.
///
/// Mindolph parity (MarkdownPreferencesPane mono-font picker): the
/// user picks a family in Preferences; CodeArea reads it. An unset or
/// empty value, or a name that doesn't resolve to an installed font,
/// quietly falls back to `monospacedSystemFont` so a stale preference
/// from another machine doesn't render the editor in an unstyled
/// substitute font.
public enum EditorFont {

    /// The five families we surface in the Preferences picker. All are
    /// either bundled with macOS or commonly installed by developer
    /// tooling. The picker also offers a "System default" entry that
    /// passes nil here.
    public static let pickerFamilies: [String] = [
        "SF Mono", "Menlo", "Monaco", "Courier New", "JetBrains Mono",
    ]

    /// The editor font currently configured in Preferences (family + size),
    /// with the same fallback chain as `resolve`. The single source of truth
    /// for the markdown / plantuml editors so the pref actually drives the
    /// rendered font (the highlighters overwrite the storage font, so this must
    /// feed the highlighter's baseFont — not just textView.font).
    public static var current: NSFont {
        resolve(family: PrefKeys.string(PrefKeys.editorFontFamily),
                size: CGFloat(PrefKeys.double(PrefKeys.editorFontSize, fallback: 13)))
    }

    /// Resolve `family` (nil = system default) at the requested point
    /// size. Falls back to `monospacedSystemFont` when the named family
    /// isn't installed.
    public static func resolve(family: String?, size: CGFloat) -> NSFont {
        if let name = family,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let font = NSFont(name: name, size: size) {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
