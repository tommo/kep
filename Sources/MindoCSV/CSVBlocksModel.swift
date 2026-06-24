import SwiftUI

/// View-model for the CSV blocks panel. Owns the editable block list + their
/// last results, and routes changes back to the editor coordinator (which holds
/// the live sheet) via two closures: `persist` (sidecar write only, on edits)
/// and `apply` (run blocks → recompute formulas → reload the grid, on Run).
public final class CSVBlocksModel: ObservableObject {
    @Published public var blocks: [CSVEvalBlock] = []
    /// Last run results, keyed by block id.
    @Published public var results: [String: CSVBlockResult] = [:]

    /// Persist the blocks to the sidecar without recomputing (cheap; on edits).
    public var persist: (([CSVEvalBlock]) -> Void)?
    /// Apply: run the blocks + recompute formulas + reload the grid; returns
    /// each block's result (in block order).
    public var apply: (([CSVEvalBlock]) -> [CSVBlockResult])?

    public init() {}

    /// Load from the sheet (on document open) and show current results.
    public func load(_ blocks: [CSVEvalBlock]) {
        self.blocks = blocks
        runAll()
    }

    public func runAll() {
        let rs = apply?(blocks) ?? []
        var byID: [String: CSVBlockResult] = [:]
        for (block, result) in zip(blocks, rs) { byID[block.id] = result }
        results = byID
    }

    public func addBlock() {
        blocks.append(CSVEvalBlock(name: uniqueName(base: "block"), source: "-- e.g. return sum(col(\"A\"))\nreturn 0"))
        persist?(blocks)
    }

    public func deleteBlock(_ id: String) {
        blocks.removeAll { $0.id == id }
        results[id] = nil
        runAll()
    }

    /// Persist edits (name/source) without recomputing — call on field changes.
    public func edited() { persist?(blocks) }

    private func uniqueName(base: String) -> String {
        let existing = Set(blocks.map(\.name))
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base)\(n)") { n += 1 }
        return "\(base)\(n)"
    }
}
