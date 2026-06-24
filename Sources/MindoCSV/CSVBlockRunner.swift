import Foundation
import MindoScript
import LuaSwift

/// Result of evaluating one sheet block.
public struct CSVBlockResult: Equatable, Sendable {
    public let name: String
    public let value: String      // display of the block's returned value
    public let output: String     // captured print() output
    public let error: String?     // nil when the block ran clean
}

/// Evaluates user-composed Lua "sheet blocks" over a CSV document. Each block is
/// a Lua chunk whose `return` value becomes the named result; blocks share one
/// VM in declaration order, so a later block can use an earlier one's global.
///
/// Sheet API exposed to blocks (on top of the formula library — SUM/AVERAGE/…):
///   cell("B2")            → a cell's value (number or string)
///   col("A") / col("Rev") → a column by letter OR header name (1-based array)
///   rows()                → list of row tables keyed by header
///   headers()             → array of header names
///   nrows() / ncols()     → body row count / column count
///   sum/avg/count/min/max/median over arrays; print(...) → block output
public enum CSVBlockRunner {

    public static func run(_ blocks: [CSVEvalBlock], over document: CSVDocument) -> [CSVBlockResult] {
        guard !blocks.isEmpty, let engine = try? LuaScriptEngine() else { return [] }
        _ = try? engine.run(LuaFormula.prelude)   // SUM/AVERAGE/MIN/MAX/…

        let headers = document.headers
        let body = document.bodyRows
        let cols = document.columnCount

        // Prefer a header-name match (user-facing); fall back to a column letter
        // so col("Revenue") and col("A") both work without ambiguity.
        func columnIndex(_ key: String) -> Int? {
            if let i = headers.firstIndex(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) { return i }
            return columnLetterIndex(key)
        }
        func columnLetterIndex(_ s: String) -> Int? {
            let u = s.uppercased()
            guard !u.isEmpty, u.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return nil }
            var idx = 0
            for ch in u.unicodeScalars { idx = idx * 26 + Int(ch.value - 65) + 1 }
            return idx - 1
        }
        func luaValue(_ s: String) -> LuaValue { Double(s).map(LuaValue.number) ?? .string(s) }

        var buffer = ""
        engine.register("__print") { args in
            buffer += args.map(display).joined(separator: "\t") + "\n"; return .nil
        }
        engine.register("__ncols") { _ in .number(Double(cols)) }
        engine.register("__nrows") { _ in .number(Double(body.count)) }
        engine.register("__headers") { _ in .array(headers.map { .string($0) }) }
        engine.register("__col") { args in
            guard let key = args.first?.stringValue, let ci = columnIndex(key) else { return .array([]) }
            return .array(body.map { ci < $0.count ? luaValue($0[ci]) : .string("") })
        }
        engine.register("__cellv") { args in
            guard let a1 = args.first?.stringValue, let ref = CSVCellRef(a1: a1),
                  ref.row >= 0, ref.row < document.rows.count,
                  ref.col >= 0, ref.col < document.rows[ref.row].count else { return .number(0) }
            return luaValue(document.rows[ref.row][ref.col])
        }
        _ = try? engine.run(Self.blockPrelude)

        var results: [CSVBlockResult] = []
        for block in blocks {
            buffer = ""
            let wrapped = "\(block.name) = (function()\n\(block.source)\nend)()"
            do {
                _ = try engine.run(wrapped)
                let v = try engine.run("return \(block.name)")
                results.append(CSVBlockResult(name: block.name, value: display(v), output: buffer, error: nil))
            } catch {
                let msg = "\(error)".replacingOccurrences(of: "\n", with: " ")
                results.append(CSVBlockResult(name: block.name, value: "", output: buffer, error: msg))
            }
        }
        return results
    }

    private static func display(_ v: LuaValue) -> String {
        switch v {
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
            return String(n)
        case .string(let s): return s
        case .bool(let b):   return b ? "true" : "false"
        case .array(let a):  return a.map(display).joined(separator: ", ")
        default:             return ""
        }
    }

    /// Lua-side sheet API built on the registered bridges + formula library.
    private static let blockPrelude = """
    print = __print
    function ncols() return __ncols() end
    function nrows() return __nrows() end
    function headers() return __headers() end
    function cell(a1) return __cellv(a1) end
    function col(k) return __col(k) end
    function rows()
      local hs = __headers()
      local cache = {}
      for _, h in ipairs(hs) do cache[h] = __col(h) end
      local n = __nrows()
      local out = {}
      for i = 1, n do
        local r = {}
        for _, h in ipairs(hs) do r[h] = cache[h][i] end
        out[#out + 1] = r
      end
      return out
    end
    sum = SUM
    avg = AVERAGE
    min = MIN
    max = MAX
    function count(t) if type(t) == 'table' then return #t end return 0 end
    function median(t)
      if type(t) ~= 'table' then return 0 end
      local nums = {}
      for _, v in ipairs(t) do if type(v) == 'number' then nums[#nums + 1] = v end end
      table.sort(nums)
      local n = #nums
      if n == 0 then return 0 end
      if n % 2 == 1 then return nums[(n + 1) // 2] end
      return (nums[n // 2] + nums[n // 2 + 1]) / 2
    end
    """
}
