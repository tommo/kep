import Foundation

/// Pure path math: express one file's location relative to another file's
/// directory. Shared by CSV cell links and markdown image/link insertion so
/// the `../`-walking logic lives in exactly one place.
public enum RelativePath {

    /// Path of `target` relative to the directory containing `source`. Returns
    /// `"file.txt"`, `"sub/file.txt"`, `"../sibling/file.txt"`, … or the
    /// absolute path when the two share no parent beyond the filesystem root
    /// (avoids absurd `../../..` chains across volumes).
    public static func from(fileAt source: URL, to target: URL) -> String {
        let baseComps = source.deletingLastPathComponent().standardizedFileURL.pathComponents
        let tgtComps = target.standardizedFileURL.pathComponents

        var i = 0
        while i < baseComps.count, i < tgtComps.count, baseComps[i] == tgtComps[i] { i += 1 }

        guard i > 1 else { return target.standardizedFileURL.path }

        let ups = Array(repeating: "..", count: baseComps.count - i)
        let downs = Array(tgtComps[i...])
        let comps = ups + downs
        return comps.isEmpty ? target.lastPathComponent : comps.joined(separator: "/")
    }
}
