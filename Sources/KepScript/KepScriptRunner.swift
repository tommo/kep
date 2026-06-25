import Foundation
import LuaSwift
import KepModel

/// Result of running a script: a human-readable output string and an optional
/// error message. Keeps `LuaValue` inside this module — callers get Strings.
public struct ScriptRunResult: Equatable, Sendable {
    public let output: String
    /// Clean, human-readable error (no Swift/LuaSwift wrapper noise), or nil.
    public let error: String?
    /// 1-based source line the error points at, when Lua reported one.
    public let errorLine: Int?
    public var ok: Bool { error == nil }
    public init(output: String, error: String?, errorLine: Int? = nil) {
        self.output = output
        self.error = error
        self.errorLine = errorLine
    }
}

/// One-call façade: run a Lua script against a mind map (+ optional KB corpus),
/// returning a String result. Mutations apply to `map` directly; the caller
/// reloads the canvas and groups undo.
public enum KepScriptRunner {
    public static func run(_ source: String,
                           on map: MindMap,
                           corpus: [(url: URL, text: String)] = [],
                           allFiles: [URL] = []) -> ScriptRunResult {
        do {
            let engine = try LuaScriptEngine()
            let api = KepLuaAPI(map: map, corpus: corpus, allFiles: allFiles)
            try api.install(on: engine)
            let value = try engine.run(source)
            return ScriptRunResult(output: describe(value), error: nil)
        } catch {
            let e = cleanError(error)
            return ScriptRunResult(output: "", error: e.message, errorLine: e.line)
        }
    }

    /// Turn a raw LuaSwift/Swift error into a clean message + source line —
    /// strips the `[string "…"]:N:` prefix, the `runtimeFailure(LuaRuntimeFailure(…))`
    /// wrapper, and surfaces the line so the editor can point at it.
    public static func cleanError(_ error: Error) -> (message: String, line: Int?) {
        if let lua = error as? LuaError {
            switch lua {
            case .runtimeFailure(let f):
                return (strip(f.message), f.line)
            case .syntaxError(let s), .runtimeError(let s),
                 .memoryError(let s), .callbackError(let s), .errorHandlerError(let s):
                return located(s)
            case .typeError(let expected, let actual):
                return ("type error: expected \(expected), got \(actual)", nil)
            case .prohibitedFunction(let name):
                return ("‘\(name)’ is not available in the sandbox", nil)
            case .instructionLimitExceeded:
                return ("stopped: instruction limit reached (possible infinite loop)", nil)
            case .cancelled:
                return ("cancelled", nil)
            default:
                return (located(String(describing: lua)).message, nil)
            }
        }
        return ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, nil)
    }

    private static func strip(_ message: String) -> String {
        message.hasPrefix("Swift callback error: ")
            ? String(message.dropFirst("Swift callback error: ".count)) : message
    }

    /// Pull the line + message out of a `[string "…"]:N: message` Lua error
    /// string; falls back to stripping just the `[string "…"]:` prefix.
    private static func located(_ s: String) -> (message: String, line: Int?) {
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let re = try? NSRegularExpression(pattern: #"\]:(\d+):\s*(.*)"#, options: [.dotMatchesLineSeparators]),
           let m = re.firstMatch(in: s, range: full) {
            return (strip(ns.substring(with: m.range(at: 2))), Int(ns.substring(with: m.range(at: 1))))
        }
        if let re = try? NSRegularExpression(pattern: #"^\[string ".*?"\]:\s*"#),
           let m = re.firstMatch(in: s, range: full) {
            return (strip(ns.substring(from: m.range.upperBound)), nil)
        }
        return (strip(s), nil)
    }

    /// Human-readable rendering of a Lua return value for the runner's output pane.
    public static func describe(_ v: LuaValue) -> String {
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
