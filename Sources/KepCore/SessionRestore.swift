import Foundation

/// Pure policy for reopening last session's tabs on launch. Kept out of the
/// session so the "Open Last Files" gate and the still-exists filter are
/// unit-testable without touching the real filesystem or UserDefaults.
public enum SessionRestore {

    /// The file paths to reopen, in saved order: empty when the user turned
    /// "Open Last Files" off, otherwise the saved paths that still exist
    /// (the caller injects the existence check).
    public static func pathsToReopen(
        savedPaths: [String],
        openLastFiles: Bool,
        exists: (String) -> Bool
    ) -> [String] {
        guard openLastFiles else { return [] }
        return savedPaths.filter(exists)
    }
}
