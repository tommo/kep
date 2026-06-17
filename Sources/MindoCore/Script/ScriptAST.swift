import Foundation

/// MindoScript expression AST. The shared CEL-style expression sublanguage used
/// by query stages, builder decorators, and `{{ }}` interpolation. See
/// `docs/MINDOSCRIPT_SPEC.md`. Block/builder/query nodes are added with the
/// line-classifier phase; this is the expression core.
public indirect enum ScriptNode: Equatable, Sendable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case null
    case identity                          // `.` — the current element in a query stage
    case variable(String)                  // `$name`
    case identifier(String)                // a bare word (source/stage keyword or builtin name — parser resolves later)
    case list([ScriptNode])
    case object([ObjectEntry])
    case call(callee: String, args: [ScriptNode])   // `name(args)`
    case member(ScriptNode, String)        // `expr.field`
    case method(ScriptNode, String, [ScriptNode])   // `expr.f(args)`  (sugar: a.f(b) == f(a,b))
    case attribute(ScriptNode, String)     // `expr@key` / `.@key`
    case index(ScriptNode, ScriptNode)     // `expr[expr]`
    case unary(String, ScriptNode)         // `!x`, `-x`
    case binary(String, ScriptNode, ScriptNode)
    case ternary(ScriptNode, ScriptNode, ScriptNode)

    public struct ObjectEntry: Equatable, Sendable {
        public let key: String
        public let value: ScriptNode
        public init(_ key: String, _ value: ScriptNode) {
            self.key = key
            self.value = value
        }
    }
}
