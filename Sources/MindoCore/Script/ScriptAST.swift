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

/// A query pipeline source — the finite set of handles a `?` pipeline starts from.
public enum ScriptSource: Equatable, Sendable {
    case nodes(String?)          // `nodes` / `nodes "MapName"`
    case backlinks(ScriptNode)   // `backlinks <expr>`
    case links(ScriptNode?)      // `links` / `links <expr>`
    case docs                    // `docs`
    case from(String)            // `from $var`
}

/// One query pipeline stage. Mutating stages (`set`/`rename`/…/`remove`) stage
/// effects; the rest filter/transform/reduce the flowing set.
public enum ScriptStage: Equatable, Sendable {
    case whereKeep(ScriptNode)
    case setAttr(String, ScriptNode)   // `set @key = expr`
    case rename(ScriptNode)
    case addChild(ScriptNode)
    case setNote(ScriptNode)
    case setLink(ScriptNode)
    case remove
    case mapEach(ScriptNode)           // `map <expr>` projection
    case sortBy(ScriptNode)
    case limit(Double)
    case distinct
    case group(ScriptNode)
    case count
    case collect
}

/// A `? source | stage | … [as $var]` pipeline.
public struct QueryBlock: Equatable, Sendable {
    public let source: ScriptSource
    public let stages: [ScriptStage]
    public let bind: String?
    public init(source: ScriptSource, stages: [ScriptStage], bind: String?) {
        self.source = source
        self.stages = stages
        self.bind = bind
    }
}

/// A top-level program element. (MapBlock builder parsing is added next.)
public enum TopLevel: Equatable, Sendable {
    case query(QueryBlock)
}
