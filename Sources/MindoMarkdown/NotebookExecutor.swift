import Foundation

/// Context handed to a notebook run (lets the host resolve the sidecar + KB).
public struct NotebookRunContext: Sendable {
    public let documentURL: URL?
    public init(documentURL: URL?) { self.documentURL = documentURL }
}

/// Run a single cell's source; returns its output. Injected by the app layer
/// (which owns MindoScript) so MindoMarkdown stays free of a scripting dep.
public typealias NotebookRunOne = @MainActor (_ source: String, _ ctx: NotebookRunContext) async -> ExecOutput

/// Run every code cell against a shared VM; returns the full outputs map.
public typealias NotebookRunAll = @MainActor (_ notebook: Notebook, _ ctx: NotebookRunContext) async -> ExecOutputs
