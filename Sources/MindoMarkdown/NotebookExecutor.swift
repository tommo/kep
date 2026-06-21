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

/// What the research agent writes into the notebook as it works. The notebook
/// model conforms; the app's agent runner authors through it.
@MainActor
public protocol NotebookAgentSink: AnyObject {
    func agentAddProse(_ text: String)
    func agentAddCode(_ code: String, output: ExecOutput)
    /// Report the source documents consulted (provenance for the block).
    func agentSetSources(_ sources: [String])
}

/// Run the research agent for `question`, authoring cells into `sink`. Injected
/// by the app (which owns the agent loop + MindoScript).
public typealias NotebookAgentRunner = @MainActor (_ question: String, _ sink: NotebookAgentSink) async -> Void
