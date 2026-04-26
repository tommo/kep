import Foundation

/// Pure-logic helpers for the workspace sidebar's row labels. Lives
/// in MindoCore (not the app target) so the extension-stripping rules
/// are unit-testable independent of SwiftUI.
public enum SidebarLabel {

    /// Strip exactly the last path extension from `name`, returning
    /// `name` unchanged when there's nothing to strip. Doesn't touch
    /// hidden-file dots (a leading `.` like `.gitignore` keeps its
    /// dot — only the *trailing* extension is removed).
    ///
    /// Examples:
    /// - `"notes.mmd"`        → `"notes"`
    /// - `"My File.org"`      → `"My File"`
    /// - `"archive.tar.gz"`   → `"archive.tar"` (only the last segment)
    /// - `"README"`           → `"README"`
    /// - `".gitignore"`       → `".gitignore"` (no trailing extension)
    /// - `"."` / `".."`       → unchanged
    public static func stripExtension(_ name: String) -> String {
        guard !name.isEmpty, name != ".", name != ".." else { return name }
        // `pathExtension` on a leading-dot file like `.gitignore` returns
        // "" — perfect, our guard handles it implicitly.
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty else { return name }
        return (name as NSString).deletingPathExtension
    }

    /// Combine `name` with the user's preference (passed in so callers
    /// don't double-read PrefKeys). Returns the cleaned label or the
    /// original when the toggle is off.
    public static func displayName(_ name: String, hideExtensions: Bool) -> String {
        hideExtensions ? stripExtension(name) : name
    }
}
