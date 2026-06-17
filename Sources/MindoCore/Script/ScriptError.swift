import Foundation

/// A position in MindoScript source (1-based line and column). Carried on every
/// token and every error so failures point at the offending text.
public struct SourceRange: Equatable, Sendable {
    public let line: Int
    public let col: Int
    public init(line: Int, col: Int) {
        self.line = line
        self.col = col
    }
}

/// The single error type MindoScript ever produces. Fail-fast and total: it is
/// returned to the host (never thrown into the UI as a crash), and a run that
/// errors commits nothing.
public struct ScriptError: Error, Equatable, CustomStringConvertible {
    public enum Phase: String, Sendable { case lex, parse, eval, handle, regex }
    public let phase: Phase
    public let message: String
    public let at: SourceRange?

    public init(phase: Phase, message: String, at: SourceRange? = nil) {
        self.phase = phase
        self.message = message
        self.at = at
    }

    public static func lex(_ m: String, line: Int, col: Int) -> ScriptError {
        ScriptError(phase: .lex, message: m, at: SourceRange(line: line, col: col))
    }
    public static func parse(_ m: String, at: SourceRange?) -> ScriptError {
        ScriptError(phase: .parse, message: m, at: at)
    }
    public static func eval(_ m: String, at: SourceRange? = nil) -> ScriptError {
        ScriptError(phase: .eval, message: m, at: at)
    }
    public static func handle(_ m: String) -> ScriptError { ScriptError(phase: .handle, message: m) }
    public static func regex(_ m: String) -> ScriptError { ScriptError(phase: .regex, message: m) }

    public var description: String {
        if let at { return "\(phase) error at \(at.line):\(at.col): \(message)" }
        return "\(phase) error: \(message)"
    }
}
