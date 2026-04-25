import Foundation
import MindoModel

/// Namespace for shared MindoCore facilities. Used as a parking spot for
/// global helpers like `applicationSupportURL`. Concrete services live in
/// their own files (`WorkspaceManager`, `Workspace`, `NodeData`).
public enum MindoCore {
    public static let storageDirectoryName = "Mindo"

    /// `~/Library/Application Support/Mindo/`
    public static var applicationSupportURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(storageDirectoryName, isDirectory: true)
    }
}
