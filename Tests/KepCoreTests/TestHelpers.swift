import Foundation

/// Build a unique scratch directory under FileManager's temporary directory.
/// Tests use this to isolate persistence side-effects between runs. The
/// caller is responsible for cleanup (typical pattern: a `defer
/// { try? FileManager.default.removeItem(at: dir) }` next to the call).
func makeScratchDirectory(prefix: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
