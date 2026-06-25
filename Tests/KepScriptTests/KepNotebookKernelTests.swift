import XCTest
import KepModel
@testable import KepScript

final class KepNotebookKernelTests: XCTestCase {

    private func kernel() throws -> KepNotebookKernel {
        try KepNotebookKernel(map: MindMap())
    }

    func testSharedGlobalsAcrossCells() throws {
        let k = try kernel()
        _ = k.run("x = 41")
        let r = k.run("return x + 1")
        XCTAssertNil(r.error)
        XCTAssertEqual(r.output, "42")
    }

    func testPrintCapture() throws {
        let k = try kernel()
        let r = k.run("print('hello')")
        XCTAssertNil(r.error)
        XCTAssertEqual(r.output, "hello")
    }

    func testPrintPlusReturn() throws {
        let k = try kernel()
        let r = k.run("print('a'); print('b'); return 2")
        XCTAssertNil(r.error)
        XCTAssertEqual(r.output, "a\nb\n2")
    }

    func testNoResultIsEmptyOutput() throws {
        let k = try kernel()
        let r = k.run("local y = 1")
        XCTAssertNil(r.error)
        XCTAssertEqual(r.output, "")
    }

    func testErrorReturnedAndKernelStaysUsable() throws {
        let k = try kernel()
        let bad = k.run("error('boom')")
        XCTAssertNotNil(bad.error)
        // Kernel must keep working for the next cell (Run-All continues).
        let good = k.run("return 7")
        XCTAssertNil(good.error)
        XCTAssertEqual(good.output, "7")
    }

    // MARK: - CodeAct primitives (agent acts through Lua)

    func testNbAuthoringHooksFire() throws {
        let k = try kernel()
        var notes: [String] = []
        var codes: [String] = []
        k.onNote = { notes.append($0) }
        k.onCode = { codes.append($0) }
        let r = k.run("nb.note('a finding'); nb.code('return 1'); return 'ok'")
        XCTAssertNil(r.error)
        XCTAssertEqual(notes, ["a finding"])
        XCTAssertEqual(codes, ["return 1"])
    }

    func testNbHooksNoopWhenUnset() throws {
        let k = try kernel()   // onNote/onCode nil → calls must not crash
        let r = k.run("nb.note('x'); nb.code('y'); return 'fine'")
        XCTAssertNil(r.error)
        XCTAssertEqual(r.output, "fine")
    }

    func testKepSearchOverCorpus() throws {
        let url = URL(fileURLWithPath: "/tmp/Extraction.md")
        let k = try KepNotebookKernel(
            map: MindMap(),
            corpus: [(url: url, text: "Grind size controls extraction time and yield.")],
            allFiles: [url])
        let hit = k.run("return #kep.search('yield')")
        XCTAssertNil(hit.error)
        XCTAssertEqual(hit.output, "1")
        XCTAssertEqual(k.run("return #kep.search('xyznevermatches')").output, "0")
    }

    func testKepSemanticSearchCallable() throws {
        let url = URL(fileURLWithPath: "/tmp/Grind.md")
        let k = try KepNotebookKernel(
            map: MindMap(),
            corpus: [(url: url, text: "Finer grind slows flow and raises extraction yield.")],
            allFiles: [url])
        // Returns a Lua array (count ≥ 0) and never errors — empty when on-device
        // embeddings aren't available; non-empty when they are.
        let r = k.run("return #kep.semanticSearch('how does particle size change extraction')")
        XCTAssertNil(r.error)
        XCTAssertNotNil(Int(r.output))
    }

    /// DOGFOOD: play a CodeAct agent over the real espresso-kb corpus — run the
    /// exact Lua actions a model would emit, observe outputs, author cells.
    /// Exercises kep.search/docs/readDoc, nb.note/nb.code, persistent globals.
    func testDogfoodCodeActSessionOverRealCorpus() throws {
        // Load the shipped example workspace as the corpus.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let kb = root.appendingPathComponent("Examples/espresso-kb")
        let files = (try FileManager.default.contentsOfDirectory(at: kb, includingPropertiesForKeys: nil))
            .filter { ["md", "csv", "puml", "mmd"].contains($0.pathExtension) }
        let corpus = files.map { (url: $0, text: (try? String(contentsOf: $0, encoding: .utf8)) ?? "") }
        let k = try KepNotebookKernel(map: MindMap(), corpus: corpus, allFiles: files)

        var notes: [String] = [], codes: [String] = []
        k.onNote = { notes.append($0) }
        k.onCode = { codes.append($0) }

        // The agent's sequence of code actions (research → read → compute → author).
        let actions: [String] = [
            // 1. orient
            "for _, d in ipairs(kep.docs()) do print(d) end",
            // 2. research — literal then meaning-based (embedding) retrieval
            "for _, h in ipairs(kep.search('grind')) do print(h) end",
            "for _, h in ipairs(kep.semanticSearch('how does particle size change extraction', 3)) do print(h) end",
            // 3. read into shared globals
            "grind = kep.readDoc('Grind'); extraction = kep.readDoc('Extraction'); print('grind '..#grind..' / extraction '..#extraction)",
            // 4. compute over a PRIOR action's global, then author a finding
            """
            local function has(t,w) return t:lower():find(w) ~= nil end
            print('inverse: '..tostring(has(grind,'inverse'))..'  yield: '..tostring(has(extraction,'yield')))
            nb.note('**Grind size is the dominant extraction lever.** Per [[Grind]], finer grind raises surface area and flow resistance, so contact time and yield climb; coarser does the reverse. [[Extraction]] lists grind first among the key variables (200-400 micron).')
            return 'noted'
            """,
            // 5. author a reusable code cell
            """
            nb.code([[
            -- Shot-time verdict from Grind.md's dial-in table (1:2 ratio)
            function verdict(s)
              if s < 20 then return 'under-extracted (sour) - grind finer'
              elseif s > 35 then return 'over-extracted (bitter) - grind coarser'
              else return 'balanced (25-35s)' end
            end
            for _, s in ipairs({18,30,40}) do print(s..'s -> '..verdict(s)) end
            ]])
            return 'authored a code cell'
            """,
        ]

        print("DOGFOOD ===== CodeAct session: 'how does grind size affect extraction?' =====")
        for (i, code) in actions.enumerated() {
            let r = k.run(code)
            print("DOGFOOD --- action \(i + 1) ---")
            if let e = r.error { print("DOGFOOD  ERROR: \(e)") }
            for line in r.output.split(separator: "\n") { print("DOGFOOD  > \(line)") }
        }
        print("DOGFOOD ===== authored \(notes.count) note(s), \(codes.count) code cell(s) =====")
        for n in notes { print("DOGFOOD  NOTE: \(n.prefix(80))…") }
        for c in codes { print("DOGFOOD  CODE:\n\(c)") }

        // It actually worked end to end:
        XCTAssertGreaterThanOrEqual(notes.count, 1, "agent authored a prose finding")
        XCTAssertGreaterThanOrEqual(codes.count, 1, "agent authored a code cell")
        // The authored code is valid Lua that runs in the same kernel.
        XCTAssertNil(k.run(codes[0]).error, "authored code cell must run")
        // Persistent globals across actions (the dependency chain).
        XCTAssertEqual(k.run("return extraction ~= nil and grind ~= nil").output, "true")
    }

    func testLoadLibraryExtendsTheArsenal() throws {
        let k = try kernel()
        // A user library can define new globals/tables AND extend `kep`.
        XCTAssertNil(k.loadLibrary("""
        function double(x) return x * 2 end
        mylib = { tri = function(x) return x * 3 end }
        function kep.shout(s) return s:upper() end
        """))
        XCTAssertEqual(k.run("return double(21)").output, "42")
        XCTAssertEqual(k.run("return mylib.tri(14)").output, "42")
        XCTAssertEqual(k.run("return kep.shout('hi')").output, "HI")
        // A broken library returns an error but leaves the kernel usable.
        XCTAssertNotNil(k.loadLibrary("this is not lua", name: "bad.lua"))
        XCTAssertEqual(k.run("return 1 + 1").output, "2")
    }

    // MARK: - Clean error UX

    func testRuntimeErrorIsCleanWithLine() throws {
        let k = try kernel()
        let r = k.run("local x = nil\nreturn x.field")
        XCTAssertEqual(r.errorLine, 2)
        XCTAssertEqual(r.error, "attempt to index a nil value (local 'x')")
        XCTAssertFalse(r.error!.contains("LuaRuntimeFailure"))   // no wrapper noise
        XCTAssertFalse(r.error!.contains("[string"))             // no source prefix
    }

    func testSyntaxErrorIsCleanWithLine() throws {
        let k = try kernel()
        let r = k.run("return 1 +")
        XCTAssertEqual(r.errorLine, 1)
        XCTAssertTrue(r.error!.contains("unexpected symbol"))
        XCTAssertFalse(r.error!.contains("syntaxError"))
    }

    func testHostCallbackErrorSurfacesCleanMessage() throws {
        let k = try kernel()
        let r = k.run("return kep.readDoc()")   // missing required arg
        XCTAssertNotNil(r.error)
        XCTAssertTrue(r.error!.contains("expected"))             // the KepScriptError message
        XCTAssertFalse(r.error!.contains("KepScriptError"))    // not the opaque NSError
    }

    func testSandboxDeniesDangerousCapabilities() throws {
        let k = try kernel()
        // The capabilities that actually let a script touch the system must be
        // unreachable. (`require` exists as a symbol but its searchers are
        // stripped by the sandbox; it's the same engine that already backs the
        // shipped run_lua tool, so notebooks add no new exposure.)
        for probe in ["os and os.execute", "io and io.open", "load", "loadstring", "dofile", "os and os.exit"] {
            let r = k.run("return (\(probe)) and 'reachable' or 'blocked'")
            XCTAssertNotEqual(r.output, "reachable", "\(probe) should be sandboxed; got \(r.output) err=\(r.error ?? "")")
        }
    }
}
