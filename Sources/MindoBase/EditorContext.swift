import Foundation
import MindoCore

/// Per-document UI state shared across editor implementations. Mirrors
/// `EditorContext` from `mindolph-base`. All fields are observable so a SwiftUI
/// view can react to them; mutations happen on the main actor.
@MainActor
public final class EditorContext: ObservableObject, Identifiable {
    public let id = UUID()

    /// File-system URL backing this editor, if any. New unsaved documents have
    /// `nil` here.
    @Published public var fileURL: URL?

    /// Display title — defaults to the file's basename, falls back to the
    /// session-supplied placeholder.
    @Published public var title: String

    /// File-type classification — drives editor routing.
    @Published public var fileType: SupportedFileType?

    /// Set whenever the editor's in-memory text differs from the on-disk copy.
    @Published public var isDirty: Bool = false

    /// Last successful save timestamp.
    @Published public var lastSavedAt: Date?

    /// Most recent user selection. Editor coordinators publish updates here so
    /// AI panes / find features can pick up "the current selection".
    @Published public var selectedText: String = ""

    public init(fileURL: URL?, title: String, fileType: SupportedFileType? = nil) {
        self.fileURL = fileURL
        self.title = title
        self.fileType = fileType
    }

    public func markDirty() { isDirty = true }

    public func markSaved(at date: Date = Date()) {
        isDirty = false
        lastSavedAt = date
    }

    public var hasOnDiskBacking: Bool { fileURL != nil }
}

/// Errors thrown by editor save / load operations.
public enum EditorError: Error, LocalizedError {
    case noFileURL
    case readFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noFileURL: return "Document has no file URL — use Save As first"
        case .readFailed(let s): return "Read failed: \(s)"
        case .writeFailed(let s): return "Write failed: \(s)"
        }
    }
}
