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
