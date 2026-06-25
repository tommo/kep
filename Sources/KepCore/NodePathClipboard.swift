import Foundation

/// Pure mapping from a node to the strings the sidebar "Copy Path" /
/// "Copy Relative Path" commands place on the pasteboard. Kept out of the
/// AppKit layer so the exact text — and the workspace-relative fallback —
/// is unit-testable without a live NSPasteboard.
public enum NodePathClipboard {

    public enum Kind {
        /// The node's absolute filesystem path.
        case absolute
        /// Path relative to the owning workspace root (falls back to the
        /// last path component when no workspace is set).
        case relative
    }

    /// The text to copy for `node` under the given command.
    public static func text(for node: NodeData, kind: Kind) -> String {
        switch kind {
        case .absolute: return node.url.path
        case .relative: return node.workspaceRelativePath
        }
    }
}
