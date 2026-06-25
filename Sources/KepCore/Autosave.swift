import Foundation

/// Pure-logic gate for save-on-blur autosave. Lives in KepCore so the
/// criteria can be unit-tested without spinning up an @Observable
/// AppSession or NotificationCenter plumbing. Deliberately takes primitive
/// inputs (not OpenDocument) so the rule can be reused / verified in
/// isolation.
public enum Autosave {
    /// True when a doc is worth flushing on a blur event:
    ///  - it must be dirty (no point writing what's already on disk),
    ///  - it must have a destination URL (silent autosave can't pick a path),
    ///  - it must round-trip through save (excludes `.unsupported`).
    public static func shouldAutosave(isDirty: Bool, hasFileURL: Bool, isSavable: Bool) -> Bool {
        return isDirty && hasFileURL && isSavable
    }
}
