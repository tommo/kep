import Foundation

/// Common protocol for any editor that wants to participate in the App's
/// shared infrastructure (save/reload routing, dirty tracking, AI selection).
///
/// Concrete editors are SwiftUI `View`s wrapping AppKit, so this protocol is
/// adopted by the document model rather than the view itself.
@MainActor
public protocol Editor: AnyObject {
    /// Backing context — drives the title bar, dirty indicators, AI panes.
    var context: EditorContext { get }

    /// Snapshot of the document's serialized form (Markdown text, mindmap
    /// `.mmd`, CSV body, etc). Used for save and AI context.
    func currentSerialization() -> String

    /// Replace the in-memory content from `text` (e.g. after Save As, external
    /// reload). Editors may interpret this as raw bytes for the file type.
    func reload(_ text: String)

    /// Persist `currentSerialization()` to `context.fileURL`. Throws if no URL
    /// is set.
    func save() throws
}

public extension Editor {
    func save() throws {
        guard let url = context.fileURL else {
            throw EditorError.noFileURL
        }
        do {
            try currentSerialization().write(to: url, atomically: true, encoding: .utf8)
            context.markSaved()
        } catch {
            throw EditorError.writeFailed(error.localizedDescription)
        }
    }
}
