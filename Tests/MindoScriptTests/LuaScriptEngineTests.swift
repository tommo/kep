import XCTest
import LuaSwift
@testable import MindoScript

final class LuaScriptEngineTests: XCTestCase {

    func testArithmetic() throws {
        let e = try LuaScriptEngine()
        XCTAssertEqual(try e.run("return 1 + 2 * 3").numberValue, 7)
    }

    func testStandardLibraryAvailable() throws {
        let e = try LuaScriptEngine()
        XCTAssertEqual(try e.run("return string.upper('hi')").stringValue, "HI")
        XCTAssertEqual(try e.run("return #('abcd')").numberValue, 4)
    }

    func testHostFunctionCallableFromLua() throws {
        let e = try LuaScriptEngine()
        e.register("double") { args in .number((args.first?.numberValue ?? 0) * 2) }
        XCTAssertEqual(try e.run("return double(21)").numberValue, 42)
    }

    func testControlFlowAndLoops() throws {
        let e = try LuaScriptEngine()
        let r = try e.run("""
            local sum = 0
            for i = 1, 10 do sum = sum + i end
            return sum
            """)
        XCTAssertEqual(r.numberValue, 55)
    }

    func testSandboxRemovesIO() throws {
        let e = try LuaScriptEngine()
        // io.* is stripped in sandboxed mode → calling it errors.
        XCTAssertThrowsError(try e.run("return io.open('/etc/passwd', 'r')"))
    }

    func testInstructionLimitInterruptsRunaway() throws {
        let e = try LuaScriptEngine(instructionLimit: 200_000)
        XCTAssertThrowsError(try e.run("while true do end"))
    }

    func testSyntaxErrorThrows() {
        let e = try? LuaScriptEngine()
        XCTAssertThrowsError(try e?.run("this is not lua !!"))
    }
}
