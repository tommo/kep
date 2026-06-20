import Foundation

/// Pure path math for CSV cell links — javamind parity with
/// `getRelatedPathInCurrentWorkspace` (CsvEditor). When a workspace file is
/// dropped into a cell we store a path relative to the CSV file's own directory
/// so the link survives the workspace being moved/renamed. Falls back to an
/// absolute path when the two files share no meaningful common root (e.g.
/// different volumes), to avoid absurd `../../..` chains.
public enum CSVLink {

    /// Path of `target` relative to the directory containing `source`. Returns
    /// `"file.txt"`, `"sub/file.txt"`, `"../sibling/file.txt"`, … or the
    /// absolute path when there's no shared parent beyond the filesystem root.
    public static func relativePath(of target: URL, fromFileAt source: URL) -> String {
        let baseComps = source.deletingLastPathComponent().standardizedFileURL.pathComponents
        let tgtComps = target.standardizedFileURL.pathComponents

        var i = 0
        while i < baseComps.count, i < tgtComps.count, baseComps[i] == tgtComps[i] { i += 1 }

        // Only the filesystem root ("/") in common → too far apart; use absolute.
        guard i > 1 else { return target.standardizedFileURL.path }

        let ups = Array(repeating: "..", count: baseComps.count - i)
        let downs = Array(tgtComps[i...])
        let comps = ups + downs
        return comps.isEmpty ? target.lastPathComponent : comps.joined(separator: "/")
    }
}
