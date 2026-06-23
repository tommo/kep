import XCTest
import MindoModel
@testable import MindoScript

final class MindoNotebookKernelTests: XCTestCase {

    private func kernel() throws -> MindoNotebookKernel {
        try MindoNotebookKernel(map: MindMap())
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

    func testMindoSearchOverCorpus() throws {
        let url = URL(fileURLWithPath: "/tmp/Extraction.md")
        let k = try MindoNotebookKernel(
            map: MindMap(),
            corpus: [(url: url, text: "Grind size controls extraction time and yield.")],
            allFiles: [url])
        let hit = k.run("return #mindo.search('yield')")
        XCTAssertNil(hit.error)
        XCTAssertEqual(hit.output, "1")
        XCTAssertEqual(k.run("return #mindo.search('xyznevermatches')").output, "0")
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
