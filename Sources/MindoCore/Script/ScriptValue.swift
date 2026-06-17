import Foundation

/// A MindoScript runtime value. Closed, mostly-immutable, `Equatable` so golden
/// tests are trivial. See `docs/MINDOSCRIPT_SPEC.md`. The only reference into
/// Mindo's live model is the opaque `.handle` / `.resultSet`; the evaluator never
/// dereferences a handle — all reads go through `MindoHost` (added later).
public indirect enum ScriptValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)              // the ONLY numeric type
    case string(String)
    case list([ScriptValue])
    case object([Entry])             // insertion-ordered key/value pairs
    case handle(ScriptHandle)
    case resultSet([ScriptHandle])

    /// One insertion-ordered object member. A struct (not a tuple) so the
    /// enclosing enum's `Equatable` synthesizes.
    public struct Entry: Equatable, Sendable {
        public let key: String
        public let value: ScriptValue
        public init(_ key: String, _ value: ScriptValue) {
            self.key = key
            self.value = value
        }
    }

    /// CEL/jq truthiness: ONLY `.null` and `.bool(false)` are falsy — `0`, `""`,
    /// `[]`, `{}` are all truthy.
    public var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        default: return true
        }
    }

    /// Canonical stringification (`str(any)`). Whole numbers print without a
    /// trailing `.0`; strings are emitted verbatim; containers get a compact form.
    public var stringified: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return ScriptValue.formatNumber(n)
        case .string(let s): return s
        case .list(let xs): return "[" + xs.map(\.stringified).joined(separator: ", ") + "]"
        case .object(let es): return "{" + es.map { "\($0.key): \($0.value.stringified)" }.joined(separator: ", ") + "}"
        case .handle(let h): return h.description
        case .resultSet(let hs): return "<resultSet \(hs.count)>"
        }
    }

    static func formatNumber(_ n: Double) -> String {
        guard n.isFinite else { return n.isNaN ? "NaN" : (n < 0 ? "-Infinity" : "Infinity") }
        if n == n.rounded() && abs(n) < 1e15 { return String(Int(n)) }
        return String(n)
    }
}

/// An opaque, generation-stamped reference into Mindo's live model. The
/// evaluator treats it as a token; the host resolves it. A stale handle (its
/// node was removed earlier in the run) is detected by `gen` mismatch and
/// surfaces as a clean `ScriptError`.
public struct ScriptHandle: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable { case topic, map, doc }
    public let kind: Kind
    public let id: Int
    public let gen: UInt

    public init(kind: Kind, id: Int, gen: UInt = 0) {
        self.kind = kind
        self.id = id
        self.gen = gen
    }

    public var description: String { "<\(kind.rawValue)#\(id)>" }
}
