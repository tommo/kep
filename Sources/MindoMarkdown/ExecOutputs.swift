import Foundation

/// One cached cell result.
public struct ExecOutput: Codable, Equatable, Sendable {
    public var text: String
    public var error: String?
    public init(text: String, error: String? = nil) {
        self.text = text
        self.error = error
    }
}

/// Cached outputs for a Research-Notebook document, keyed by cell content hash
/// so an edited cell's stale output is detected (the key won't be present).
/// Persisted as a hidden sidecar next to the `.md` (mirrors the CSV sidecar
/// convention) so the markdown itself stays VCS-clean.
public struct ExecOutputs: Codable, Equatable, Sendable {
    public var outputs: [String: ExecOutput]
    public init(outputs: [String: ExecOutput] = [:]) { self.outputs = outputs }

    public func output(forHash hash: String) -> ExecOutput? { outputs[hash] }
    public mutating func set(_ output: ExecOutput, forHash hash: String) { outputs[hash] = output }

    /// Drop cached outputs whose cells no longer exist (call after a run with
    /// the current set of live hashes) so the sidecar doesn't grow unbounded.
    public mutating func prune(keeping liveHashes: Set<String>) {
        outputs = outputs.filter { liveHashes.contains($0.key) }
    }
}

public enum ExecOutputsStore {
    /// Hidden sidecar URL for a document: `.<name>.outputs.json` beside it.
    public static func sidecarURL(for document: URL) -> URL {
        document.deletingLastPathComponent()
            .appendingPathComponent("." + document.lastPathComponent + ".outputs.json")
    }

    public static func load(for document: URL) -> ExecOutputs {
        guard let data = try? Data(contentsOf: sidecarURL(for: document)),
              let decoded = try? JSONDecoder().decode(ExecOutputs.self, from: data)
        else { return ExecOutputs() }
        return decoded
    }

    public static func save(_ outputs: ExecOutputs, for document: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(outputs).write(to: sidecarURL(for: document), options: .atomic)
    }
}
