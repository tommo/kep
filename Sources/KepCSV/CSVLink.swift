import Foundation
import KepCore

/// Pure path math for CSV cell links — javamind parity with
/// `getRelatedPathInCurrentWorkspace` (CsvEditor). When a workspace file is
/// dropped into a cell we store a path relative to the CSV file's own directory
/// so the link survives the workspace being moved/renamed.
public enum CSVLink {

    /// Path of `target` relative to the directory containing `source` — thin
    /// wrapper over the shared [RelativePath] helper (kept for call-site
    /// readability: "the link from this CSV to that file").
    public static func relativePath(of target: URL, fromFileAt source: URL) -> String {
        RelativePath.from(fileAt: source, to: target)
    }
}
