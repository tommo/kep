import Foundation
import MindoModel

/// A persistent-VM Lua kernel for the Research Notebook: globals set in one
/// cell are visible to the next (shared state across a Run-All), and `print(…)`
/// output is captured (MindoLuaAPI has no print). One kernel == one notebook
/// run session; make a fresh kernel for an isolated single-cell run.
public final class MindoNotebookKernel {
    private let engine: LuaScriptEngine
    private var printBuffer: [String] = []

    public init(map: MindMap,
                corpus: [(url: URL, text: String)] = [],
                allFiles: [URL] = []) throws {
        engine = try LuaScriptEngine()
        // Capture print() into a buffer that `run` drains per cell.
        engine.register("print") { [weak self] args in
            self?.printBuffer.append(args.map(MindoScriptRunner.describe).joined(separator: "\t"))
            return .nil
        }
        try MindoLuaAPI(map: map, corpus: corpus, allFiles: allFiles).install(on: engine)
    }

    /// Run one cell against the shared VM. Output = captured prints, then the
    /// return value (omitted when there's nothing to show). Errors are returned,
    /// not thrown, and the kernel stays usable for the next cell.
    public func run(_ source: String) -> ScriptRunResult {
        printBuffer.removeAll(keepingCapacity: true)
        do {
            let value = try engine.run(source)
            let ret = MindoScriptRunner.describe(value)
            let printed = printBuffer.joined(separator: "\n")
            let out: String
            if printed.isEmpty {
                out = (ret == "(no result)") ? "" : ret
            } else {
                out = (ret == "(no result)") ? printed : printed + "\n" + ret
            }
            return ScriptRunResult(output: out, error: nil)
        } catch {
            return ScriptRunResult(output: printBuffer.joined(separator: "\n"),
                                   error: String(describing: error))
        }
    }
}
