import Foundation
import LuaSwift

/// Lua-backed scripting for Mindo. Thin wrapper over LuaSwift's sandboxed engine
/// (vendored Lua — no system dependency, dangerous `io`/`os.execute` removed)
/// with CPU + VM-memory guards. The host registers `mindo.*` functions that
/// operate on mind maps and the knowledge base. This is NOT a hand-rolled
/// language — Lua is the language.
public final class LuaScriptEngine {
    private let engine: LuaEngine

    /// - Parameters:
    ///   - instructionLimit: CPU guard — Lua VM instructions before a runaway
    ///     script is interrupted (0 = unlimited).
    ///   - vmMemoryLimitBytes: ceiling on total Lua VM allocation (0 = disabled).
    public init(instructionLimit: Int = 5_000_000,
                vmMemoryLimitBytes: Int = 128 * 1024 * 1024) throws {
        var config = LuaEngineConfiguration.default
        config.sandboxed = true
        config.vmMemoryLimit = vmMemoryLimitBytes
        engine = try LuaEngine(configuration: config)
        if instructionLimit > 0 { engine.setInstructionLimit(instructionLimit) }
    }

    /// Expose a Swift closure to scripts as a global function `name`.
    public func register(_ name: String, _ fn: @escaping ([LuaValue]) throws -> LuaValue) {
        engine.registerFunction(name: name, callback: fn)
    }

    /// Run script source, returning its `return` value (`.nil` if none).
    @discardableResult
    public func run(_ script: String) throws -> LuaValue {
        try engine.evaluate(script)
    }
}
