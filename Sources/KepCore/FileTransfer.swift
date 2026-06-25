import Foundation

/// Pure destination-naming for copy/paste/move of files between folders and
/// workspaces. Keeps the original name when it's free in the target folder,
/// otherwise falls back to the same " copy" / " copy N" sequence the
/// Duplicate action uses. Filesystem-free (caller injects `exists`) so the
/// collision rule is unit-testable.
public enum FileTransfer {

    /// Where an item named `name` should land in `directory`: `name` itself
    /// when nothing collides, else the next non-colliding " copy" variant.
    public static func destinationURL(
        forItemNamed name: String,
        in directory: URL,
        exists: (URL) -> Bool
    ) -> URL {
        let direct = directory.appendingPathComponent(name)
        if !exists(direct) { return direct }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return DuplicateName.uniqueURL(in: directory, stem: stem, ext: ext, exists: exists)
    }

    /// Whether moving `source` into `directory` is a no-op or illegal:
    /// - already directly inside `directory` (same parent) → nothing to do
    /// - `directory` is `source` itself or nested within it → would orphan
    ///   the subtree.
    /// Returns true when the move should be BLOCKED.
    public static func isRedundantOrInvalidMove(source: URL, intoDirectory directory: URL) -> Bool {
        // Compare by path so trailing-slash differences from
        // deletingLastPathComponent() don't break equality.
        let srcPath = source.standardizedFileURL.path
        let dirPath = directory.standardizedFileURL.path
        let srcParent = source.standardizedFileURL.deletingLastPathComponent().path
        if srcParent == dirPath { return true }                       // already there
        if srcPath == dirPath { return true }                         // into itself
        // Into a descendant of source (move a folder inside itself).
        return dirPath.hasPrefix(srcPath + "/")
    }
}
