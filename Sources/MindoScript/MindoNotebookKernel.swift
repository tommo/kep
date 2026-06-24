import Foundation
import MindoModel

/// A persistent-VM Lua kernel for the Research Notebook: globals set in one
/// cell are visible to the next (shared state across a Run-All), and `print(…)`
/// output is captured (MindoLuaAPI has no print). One kernel == one notebook
/// run session; make a fresh kernel for an isolated single-cell run.
public final class MindoNotebookKernel {
    private let engine: LuaScriptEngine
    private var printBuffer: [String] = []

    /// Authoring hooks for the CodeAct notebook agent: Lua `nb.note(md)` /
    /// `nb.code(src)` call these to emit notebook cells. Set by the host around
    /// an agent run; nil the rest of the time (the calls then no-op), so a user's
    /// own code can't accidentally author cells.
    public var onNote: ((String) -> Void)?
    public var onCode: ((String) -> Void)?

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
        // `nb` authoring API (CodeAct): the agent's code emits notebook cells.
        engine.register("__nb_note") { [weak self] a in
            if let s = a.first?.stringValue { self?.onNote?(s) }; return .nil
        }
        engine.register("__nb_code") { [weak self] a in
            if let s = a.first?.stringValue { self?.onCode?(s) }; return .nil
        }
        try engine.run("nb = { note = __nb_note, code = __nb_code }")
    }

    /// Load a user library into the session — runs `source` after the built-in
    /// `mindo`/`nb` API is set up, so it can define new globals or extend `mindo`
    /// (e.g. `function mindo.wordcount(s) … end`). Returns an error string if the
    /// library failed to load; the kernel stays usable (a broken library just
    /// doesn't add its functions). Call once per kernel, before running cells.
    @discardableResult
    public func loadLibrary(_ source: String, name: String = "notebook.lua") -> String? {
        do { _ = try engine.run(source); return nil }
        catch { return "\(name): \(error)" }
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
