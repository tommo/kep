import Foundation
import LuaSwift

/// A spreadsheet-formula evaluator that delegates all arithmetic, precedence,
/// comparisons, string ops and function calls to the embedded Lua engine —
/// mindo never hand-rolls an expression language (see LuaScriptEngine). A
/// formula like `=SUM(A1:A10)*1.1` is transpiled to Lua (`SUM(__range("A1",
/// "A10"))*1.1`) and `engine.evaluate`d.
///
/// Generic over the data source via two closures, so it has no CSV/grid
/// dependency: `content(a1)` returns a cell's raw string (a formula or a
/// literal), and `expandRange(a, b)` lists the A1 refs a range covers. The
/// host (MindoCSV) supplies both.
public final class LuaFormula {
    public enum Value: Equatable, Sendable {
        case number(Double)
        case text(String)
        case bool(Bool)
        case empty
        case error(String)
    }

    private let content: (String) -> String?
    private let expandRange: (String, String) -> [String]
    private let engine: LuaScriptEngine
    private var cache: [String: Value] = [:]
    private var resolving: Set<String> = []

    public init(content: @escaping (String) -> String?,
                expandRange: @escaping (String, String) -> [String]) throws {
        self.content = content
        self.expandRange = expandRange
        self.engine = try LuaScriptEngine()
        registerBridges()
        _ = try? engine.run(Self.prelude)
    }

    // MARK: - Public API

    /// The computed value of cell `a1` (evaluating its formula if it has one).
    public func value(of a1: String) -> Value {
        if let v = cache[a1] { return v }
        guard !resolving.contains(a1) else { return .error("#CIRCULAR") }
        let raw = (content(a1) ?? "")
        let v: Value
        if raw.hasPrefix("=") {
            resolving.insert(a1)
            v = evaluate(raw)
            resolving.remove(a1)
        } else {
            v = Self.literal(raw)
        }
        cache[a1] = v
        return v
    }

    /// Evaluate a formula string (`"=…"` or a bare expression). Dependencies are
    /// resolved in Swift FIRST and cached, so the Lua run's `__cell`/`__range`
    /// bridges only read the cache and never re-enter the VM. Errors in
    /// referenced cells propagate; circular references are reported.
    public func evaluate(_ formula: String) -> Value {
        let expr = formula.hasPrefix("=") ? String(formula.dropFirst()) : formula
        let t = Self.transpile(expr)
        // Pre-resolve scalar refs and every cell each range covers.
        var deps = t.cells
        for (a, b) in t.ranges { deps.append(contentsOf: expandRange(a, b)) }
        for ref in deps {
            if case .error(let e) = value(of: ref) { return .error(e) }
        }
        do {
            return Self.fromLua(try engine.run("return \(t.lua)"))
        } catch {
            return .error("#ERROR")
        }
    }

    /// Invalidate the memoized values — call after any cell edit before a
    /// recompute pass.
    public func invalidate() { cache.removeAll(keepingCapacity: true) }

    /// Define a named global in the engine so formulas can reference it by name
    /// (e.g. a sheet block `total` → `=total`). The transpiler leaves bare
    /// identifiers as Lua globals, so this is all the wiring `=total` needs.
    public func define(_ name: String, _ value: Value) {
        switch value {
        case .number(let n): _ = try? engine.run("\(name) = \(n)")
        case .bool(let b):   _ = try? engine.run("\(name) = \(b)")
        case .text(let s):   _ = try? engine.run("\(name) = \(Self.luaString(s))")
        case .empty, .error: _ = try? engine.run("\(name) = nil")
        }
    }

    /// A Lua double-quoted string literal with the contents escaped.
    private static func luaString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Display string for a value (what lands in the plain `.csv`).
    public static func display(_ v: Value) -> String {
        switch v {
        case .number(let n): return formatNumber(n)
        case .text(let s):   return s
        case .bool(let b):   return b ? "TRUE" : "FALSE"
        case .empty:         return ""
        case .error(let e):  return e
        }
    }

    // MARK: - Lua bridges (read from the pre-resolved cache, never recurse)

    /// Cache-only lookup used by the Lua bridges — never evaluates (deps are
    /// pre-resolved in `evaluate`), so running a formula can't re-enter the VM.
    private func cached(_ a1: String) -> Value { cache[a1] ?? .empty }

    private func registerBridges() {
        engine.register("__cell") { [weak self] args in
            guard let self, let a1 = args.first?.stringValue else { return .number(0) }
            switch self.cached(a1) {
            case .number(let n): return .number(n)
            case .text(let s):   return .string(s)
            case .bool(let b):   return .bool(b)
            case .empty:         return .number(0)          // blank acts as 0 in arithmetic
            case .error(let e):  return .string(e)
            }
        }
        engine.register("__range") { [weak self] args in
            guard let self, args.count >= 2,
                  let a = args[0].stringValue, let b = args[1].stringValue else { return .array([]) }
            // Ranges drop blank cells (Excel semantics): SUM/COUNT/AVERAGE ignore them.
            var out: [LuaValue] = []
            for ref in self.expandRange(a, b) {
                switch self.cached(ref) {
                case .number(let n): out.append(.number(n))
                case .text(let s):   out.append(.string(s))
                case .bool(let x):   out.append(.bool(x))
                case .empty:         continue
                case .error(let e):  out.append(.string(e))
                }
            }
            return .array(out)
        }
    }

    // MARK: - Literal parsing & Lua conversion

    private static func literal(_ raw: String) -> Value {
        if raw.isEmpty { return .empty }
        if let n = Double(raw) { return .number(n) }
        return .text(raw)
    }

    private static func fromLua(_ v: LuaValue) -> Value {
        if let n = v.numberValue { return .number(n) }
        if let b = v.boolValue { return .bool(b) }
        if let s = v.stringValue { return s.isEmpty ? .empty : .text(s) }
        return .empty
    }

    private static func formatNumber(_ n: Double) -> String {
        guard n.isFinite else { return "#NUM" }
        if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
        var s = String(n)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return s
    }

    // MARK: - Transpile (formula text → Lua), collecting referenced cells

    /// Rewrite a spreadsheet expression into Lua, returning the Lua source and
    /// the list of individual cell refs it touches (ranges expanded). Cell refs
    /// become `__cell("A1")`, ranges become `__range("A1","B2")`, Excel `<>`/`=`/
    /// `&` map to Lua `~=`/`==`/`..`. String literals and function names pass
    /// through untouched. Lua (not us) does the actual parsing/evaluation.
    static func transpile(_ expr: String) -> (lua: String, cells: [String], ranges: [(String, String)]) {
        var out = ""
        var cells: [String] = []
        var ranges: [(String, String)] = []
        let chars = Array(expr)
        var i = 0
        func isIdentStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
        func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "$" }
        func isCellRefToken(_ s: String) -> Bool {
            // letters then digits, e.g. A1, $B$2 — distinguishes refs from
            // function names (SUM) and keywords (true).
            var seenLetter = false, seenDigit = false
            for ch in s where ch != "$" {
                if ch.isLetter { if seenDigit { return false }; seenLetter = true }
                else if ch.isNumber { seenDigit = true }
                else { return false }
            }
            return seenLetter && seenDigit
        }

        while i < chars.count {
            let c = chars[i]
            // String literal: copy through, converting Excel "" escape to Lua \".
            if c == "\"" {
                out.append("\"")
                i += 1
                while i < chars.count {
                    if chars[i] == "\"" {
                        if i + 1 < chars.count, chars[i + 1] == "\"" { out.append("\\\""); i += 2; continue }
                        out.append("\""); i += 1; break
                    }
                    if chars[i] == "\\" { out.append("\\\\"); i += 1; continue }
                    out.append(chars[i]); i += 1
                }
                continue
            }
            // Identifier / cell-ref / range / keyword.
            if isIdentStart(c) {
                var j = i
                var ident = ""
                while j < chars.count, isIdent(chars[j]) { ident.append(chars[j]); j += 1 }
                // Skip spaces to peek the next significant char.
                var k = j
                while k < chars.count, chars[k] == " " { k += 1 }
                let followedByParen = k < chars.count && chars[k] == "("
                if !followedByParen, isCellRefToken(ident) {
                    // Range? cellref : cellref
                    if k < chars.count, chars[k] == ":" {
                        var m = k + 1
                        while m < chars.count, chars[m] == " " { m += 1 }
                        var ident2 = ""
                        while m < chars.count, isIdent(chars[m]) { ident2.append(chars[m]); m += 1 }
                        if isCellRefToken(ident2) {
                            let a = ident.replacingOccurrences(of: "$", with: "")
                            let b = ident2.replacingOccurrences(of: "$", with: "")
                            out.append("__range(\"\(a)\",\"\(b)\")")
                            ranges.append((a, b))
                            i = m
                            continue
                        }
                    }
                    let a = ident.replacingOccurrences(of: "$", with: "")
                    out.append("__cell(\"\(a)\")")
                    if !cells.contains(a) { cells.append(a) }
                    i = j
                    continue
                }
                // Keyword normalisation; otherwise a function name — pass through.
                switch ident.uppercased() {
                case "TRUE":  out.append("true")
                case "FALSE": out.append("false")
                default:      out.append(ident)
                }
                i = j
                continue
            }
            // Operators that differ between Excel and Lua. Two-char comparisons
            // (<=, >=, <>) must be matched before the lone '=' → '==' rule, or
            // ">=" would become ">==".
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if c == "<" {
                if next == "=" { out.append("<="); i += 2; continue }
                if next == ">" { out.append("~="); i += 2; continue }
                out.append("<"); i += 1; continue
            }
            if c == ">" {
                if next == "=" { out.append(">="); i += 2; continue }
                out.append(">"); i += 1; continue
            }
            if c == "&" { out.append(".."); i += 1; continue }
            if c == "=" {
                if next == "=" { out.append("=="); i += 2; continue }   // Excel '=' equality
                out.append("=="); i += 1; continue
            }
            out.append(c)
            i += 1
        }
        return (out, cells, ranges)
    }

    /// Lua prelude defining the spreadsheet functions over numbers + range
    /// tables. Ranges arrive as Lua arrays; scalars as numbers/strings.
    /// Public so the CSV block runner reuses the same SUM/AVERAGE/… library.
    public static let prelude = """
    local function nums(t)
      local r = {}
      if type(t) == 'table' then for _,v in ipairs(t) do if type(v)=='number' then r[#r+1]=v end end
      elseif type(t)=='number' then r[1]=t end
      return r
    end
    local function flat(args)
      local r = {}
      for _,a in ipairs(args) do
        if type(a)=='table' then for _,v in ipairs(a) do r[#r+1]=v end
        else r[#r+1]=a end
      end
      return r
    end
    function SUM(...) local s=0 for _,v in ipairs(flat({...})) do if type(v)=='number' then s=s+v end end return s end
    function COUNT(...) local n=0 for _,v in ipairs(flat({...})) do if type(v)=='number' then n=n+1 end end return n end
    function COUNTA(...) local n=0 for _,v in ipairs(flat({...})) do if v~=nil and v~='' then n=n+1 end end return n end
    function AVERAGE(...) local f=flat({...}) local s,n=0,0 for _,v in ipairs(f) do if type(v)=='number' then s=s+v;n=n+1 end end if n==0 then return 0 end return s/n end
    AVG = AVERAGE
    function MIN(...) local m for _,v in ipairs(flat({...})) do if type(v)=='number' and (m==nil or v<m) then m=v end end return m or 0 end
    function MAX(...) local m for _,v in ipairs(flat({...})) do if type(v)=='number' and (m==nil or v>m) then m=v end end return m or 0 end
    function IF(c,a,b) if c then return a else return b end end
    function ROUND(x,n) n=n or 0 local p=10^n return math.floor(x*p+0.5)/p end
    function ABS(x) return math.abs(x) end
    function SQRT(x) return math.sqrt(x) end
    function AND(...) for _,v in ipairs({...}) do if not v then return false end end return true end
    function OR(...) for _,v in ipairs({...}) do if v then return true end end return false end
    function NOT(x) return not x end
    function CONCAT(...) local s='' for _,v in ipairs(flat({...})) do s=s..tostring(v) end return s end
    CONCATENATE = CONCAT
    function POWER(x,y) return x^y end
    function MOD(a,b) return a % b end
    function INT(x) return math.floor(x) end
    function CEILING(x) return math.ceil(x) end
    function FLOOR(x) return math.floor(x) end
    function ROUNDUP(x,n) n=n or 0 local p=10^n if x<0 then return math.floor(x*p)/p else return math.ceil(x*p)/p end end
    function ROUNDDOWN(x,n) n=n or 0 local p=10^n if x<0 then return math.ceil(x*p)/p else return math.floor(x*p)/p end end
    local function slen(s) s=tostring(s) if utf8 then return utf8.len(s) or #s end return #s end
    function LEN(s) return slen(s) end
    function UPPER(s) return string.upper(tostring(s)) end
    function LOWER(s) return string.lower(tostring(s)) end
    function TRIM(s) return (tostring(s):gsub('^%s+',''):gsub('%s+$','')) end
    function LEFT(s,n) n=n or 1 return string.sub(tostring(s),1,math.max(0,n)) end
    function RIGHT(s,n) n=n or 1 s=tostring(s) return string.sub(s, #s-math.max(0,n)+1) end
    function MID(s,start,n) s=tostring(s) return string.sub(s, start, start+math.max(0,n)-1) end
    """
}
