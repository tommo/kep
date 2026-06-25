import Foundation

/// Live access to an OPEN CSV editor's in-memory sheet, so agent/bridge CSV
/// tools operate on unsaved editor state and the grid updates immediately —
/// instead of round-tripping through disk (which ignores unsaved edits and can
/// clobber them on reload). The CSV editor's coordinator conforms; the host
/// registers it per document URL and prefers it over the disk path.
public protocol CSVLiveBridge: AnyObject {
    /// A cell's formula source (if any) or baked value, from the live sheet.
    func liveReadCell(_ a1: String) -> String?
    /// Set a cell (literal or "=formula") on the live sheet, growing rows to fit;
    /// updates the grid + marks the doc dirty (one undo step). Returns success.
    func liveSetCell(_ a1: String, value: String) -> Bool
    /// Append a named Lua sheet block to the live sheet, run + recompute, and
    /// return its computed result (or an error).
    func liveAddBlock(name: String, source: String) -> String
}
