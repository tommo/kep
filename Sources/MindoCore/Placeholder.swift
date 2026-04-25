import Foundation
import MindoModel

/// Placeholder. Real workspace/project services land in P2.
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
