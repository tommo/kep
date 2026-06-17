import Foundation
import LuaSwift
import MindoModel

/// Result of running a script: a human-readable output string and an optional
/// error message. Keeps `LuaValue` inside this module — callers get Strings.
public struct ScriptRunResult: Equatable, Sendable {
    public let output: String
    public let error: String?
    public var ok: Bool { error == nil }
    public init(output: String, error: String?) {
        self.output = output
        self.error = error
    }
}

/// One-call façade: run a Lua script against a mind map (+ optional KB corpus),
/// returning a String result. Mutations apply to `map` directly; the caller
/// reloads the canvas and groups undo.
public enum MindoScriptRunner {
    public static func run(_ source: String,
                           on map: MindMap,
                           corpus: [(url: URL, text: String)] = [],
                           allFiles: [URL] = []) -> ScriptRunResult {
        do {
            let engine = try LuaScriptEngine()
            let api = MindoLuaAPI(map: map, corpus: corpus, allFiles: allFiles)
            try api.install(on: engine)
            let value = try engine.run(source)
            return ScriptRunResult(output: describe(value), error: nil)
        } catch {
            return ScriptRunResult(output: "", error: String(describing: error))
        }
    }

    /// Human-readable rendering of a Lua return value for the runner's output pane.
    static func describe(_ v: LuaValue) -> String {
        switch v {
        case .nil: return "(no result)"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .string(let s): return s
        case .array(let xs): return "[" + xs.map(describe).joined(separator: ", ") + "]"
        case .table(let t): return "{" + t.map { "\($0.key) = \(describe($0.value))" }.joined(separator: ", ") + "}"
        case .complex(let re, let im): return "\(re)+\(im)i"
        default: return "\(v)"
        }
    }
}
