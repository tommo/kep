import Foundation
import MindoCore
import MindoMindMap

/// Persists which file-backed tabs were open when the app last quit, plus
/// which one was active. Untitled / unsaved scratch documents aren't
/// persisted (they have no fileURL to round-trip through). Mirrors what
/// SceneRestore.java does for window-state restoration.
extension AppSession {

    private static let openTabsKey = "mindo.session.openTabs"
    private static let activeTabKey = "mindo.session.activeTab"

    /// Snapshot the current tab state to UserDefaults. Call after every
    /// open / close / activate so a crash doesn't lose the layout.
    func persistOpenTabs() {
        let urls = openDocuments.compactMap { $0.fileURL?.path }
        UserDefaults.standard.set(urls, forKey: Self.openTabsKey)
        if let id = activeDocumentID,
           let active = openDocuments.first(where: { $0.id == id })?.fileURL?.path {
            UserDefaults.standard.set(active, forKey: Self.activeTabKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeTabKey)
        }
    }

    /// Re-open the tabs we persisted last quit. Skips files that no
    /// longer exist on disk (the workspace tree has already trimmed
    /// stale workspaces; this does the same for individual files).
    func restoreOpenTabs() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.openTabsKey) ?? []
        let activePath = UserDefaults.standard.string(forKey: Self.activeTabKey)
        let fm = FileManager.default
        // Gated by the "Open Last Files" pref; only reopens files still on disk.
        let paths = SessionRestore.pathsToReopen(
            savedPaths: saved,
            openLastFiles: PrefKeys.bool(PrefKeys.openLastFiles, fallback: true),
            exists: { fm.fileExists(atPath: $0) })
        for path in paths {
            // Each restored file is its own tab — never reuse, or they'd all
            // collapse onto one.
            open(url: URL(fileURLWithPath: path), inNewTab: true)
        }
        if let activePath,
           let id = openDocuments.first(where: { $0.fileURL?.path == activePath })?.id {
            activeDocumentID = id
        }
    }
}
