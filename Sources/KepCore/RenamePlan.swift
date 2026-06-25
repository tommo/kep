import Foundation

/// The outcome of resolving a sidebar rename against the names already in the
/// target directory. Pure so the collision rule is unit-testable without the
/// filesystem (the caller injects the existence check).
public enum RenameOutcome: Equatable {
    /// Nothing to do — the new name was empty or equal to the current one.
    case unchanged
    /// The name is free; rename straight to it.
    case ok(String)
    /// The name is taken. `suggestion` is a unique " 2"/" 3"… variant the UI
    /// can offer instead of failing with a cryptic move error.
    case collision(requested: String, suggestion: String)
}

public enum RenamePlan {

    /// Decide what a rename to `desired` should do, given the `current` name
    /// and an `exists` check over candidate names in the same directory.
    public static func resolve(
        current: String,
        desired raw: String,
        exists: (String) -> Bool
    ) -> RenameOutcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != current else { return .unchanged }
        guard exists(trimmed) else { return .ok(trimmed) }
        return .collision(requested: trimmed, suggestion: uniqueName(for: trimmed, exists: exists))
    }

    /// First free `<stem> N.<ext>` (N≥2), preserving any extension —
    /// "notes.md" → "notes 2.md", "folder" → "folder 2". Skips names that
    /// already exist, so a directory with "notes 2.md" yields "notes 3.md".
    public static func uniqueName(for name: String, exists: (String) -> Bool) -> String {
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var n = 2
        while true {
            let candidate = "\(stem) \(n)\(suffix)"
            if !exists(candidate) { return candidate }
            n += 1
        }
    }
}
