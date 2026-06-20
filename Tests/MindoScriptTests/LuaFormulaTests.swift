import XCTest
@testable import MindoScript

/// The Lua-backed spreadsheet formula evaluator. A1 refs / ranges resolve via
/// the injected `content` closure; Lua does all arithmetic, comparison, string
/// ops and functions. Pure + headless.
final class LuaFormulaTests: XCTestCase {

    /// Build an evaluator over a fixed A1→content map. Ranges expand with a
    /// simple A1 parser local to the test.
    private func make(_ cells: [String: String]) throws -> LuaFormula {
        try LuaFormula(
            content: { cells[$0] },
            expandRange: { a, b in Self.expand(a, b) }
        )
    }

    // Minimal A1 range expansion for the tests (mirrors CSVCellRef).
    private static func parse(_ a1: String) -> (r: Int, c: Int)? {
        var letters = "", digits = ""
        for ch in a1 { if ch.isLetter { letters.append(ch) } else if ch.isNumber { digits.append(ch) } }
        guard !letters.isEmpty, let row = Int(digits) else { return nil }
        var col = 0
        for ch in letters.uppercased() { col = col * 26 + Int(ch.asciiValue! - 64) }
        return (row - 1, col - 1)
    }
    private static func label(_ c: Int) -> String {
        var n = c, s = ""
        repeat { s = String(UnicodeScalar(UInt8(65 + n % 26))) + s; n = n / 26 - 1 } while n >= 0
        return s
    }
    private static func expand(_ a: String, _ b: String) -> [String] {
        guard let pa = parse(a), let pb = parse(b) else { return [] }
        var out: [String] = []
        for r in min(pa.r, pb.r)...max(pa.r, pb.r) {
            for c in min(pa.c, pb.c)...max(pa.c, pb.c) { out.append("\(label(c))\(r + 1)") }
        }
        return out
    }

    private func num(_ f: LuaFormula, _ formula: String, _ expected: Double, line: UInt = #line) {
        guard case .number(let n) = f.evaluate(formula) else {
            return XCTFail("expected number from \(formula), got \(f.evaluate(formula))", line: line)
        }
        XCTAssertEqual(n, expected, accuracy: 1e-9, line: line)
    }

    func testArithmeticAndRefs() throws {
        let f = try make(["A1": "10", "B1": "5"])
        num(f, "=A1+B1", 15)
        num(f, "=A1-B1", 5)
        num(f, "=A1*B1", 50)
        num(f, "=A1/B1", 2)
        num(f, "=2^10", 1024)
        num(f, "=(A1+B1)*2", 30)
        num(f, "=A1*1.1", 11)
    }

    func testRangeFunctions() throws {
        let f = try make(["B10": "100", "B11": "150", "B12": "120", "B13": "text", "B14": ""])
        num(f, "=SUM(B10:B12)", 370)
        num(f, "=AVERAGE(B10:B12)", 370.0 / 3.0)
        num(f, "=MIN(B10:B12)", 100)
        num(f, "=MAX(B10:B12)", 150)
        num(f, "=COUNT(B10:B14)", 3)      // text + blank ignored
        num(f, "=SUM(B10:B14)", 370)      // text + blank ignored
    }

    func testIfAndComparisons() throws {
        let f = try make(["A21": "85", "A22": "45"])
        XCTAssertEqual(f.evaluate("=IF(A21>=60,\"Pass\",\"Fail\")"), .text("Pass"))
        XCTAssertEqual(f.evaluate("=IF(A22>=60,\"Pass\",\"Fail\")"), .text("Fail"))
        XCTAssertEqual(f.evaluate("=IF(A21=85,1,0)"), .number(1))   // Excel '=' equality
        XCTAssertEqual(f.evaluate("=IF(A21<>85,1,0)"), .number(0))  // '<>' inequality
    }

    func testStringConcat() throws {
        let f = try make(["A1": "Hello", "B1": "World"])
        XCTAssertEqual(f.evaluate("=A1&\" \"&B1"), .text("Hello World"))
        XCTAssertEqual(f.evaluate("=CONCAT(A1,B1)"), .text("HelloWorld"))
    }

    func testNestedFormulaCells() throws {
        // C1 = A1+B1; D1 = C1*2 — chained formula references resolve.
        let f = try make(["A1": "3", "B1": "4", "C1": "=A1+B1", "D1": "=C1*2"])
        XCTAssertEqual(f.value(of: "C1"), .number(7))
        XCTAssertEqual(f.value(of: "D1"), .number(14))
    }

    func testCircularReferenceIsReported() throws {
        let f = try make(["A1": "=B1", "B1": "=A1"])
        if case .error = f.value(of: "A1") {} else { XCTFail("expected circular error") }
    }

    func testRound() throws {
        let f = try make(["A1": "10", "B1": "3"])
        num(f, "=ROUND(A1/B1,2)", 3.33)
    }

    func testDisplayFormatting() {
        XCTAssertEqual(LuaFormula.display(.number(200)), "200")     // no trailing .0
        XCTAssertEqual(LuaFormula.display(.number(3.5)), "3.5")
        XCTAssertEqual(LuaFormula.display(.text("hi")), "hi")
        XCTAssertEqual(LuaFormula.display(.bool(true)), "TRUE")
        XCTAssertEqual(LuaFormula.display(.empty), "")
        XCTAssertEqual(LuaFormula.display(.error("#CIRCULAR")), "#CIRCULAR")
    }

    func testTranspile() {
        let t = LuaFormula.transpile("SUM(A1:B2)+C3*2")
        XCTAssertTrue(t.lua.contains("__range(\"A1\",\"B2\")"))
        XCTAssertTrue(t.lua.contains("__cell(\"C3\")"))
        XCTAssertEqual(t.ranges.count, 1)
        XCTAssertEqual(t.cells, ["C3"])
    }
}
