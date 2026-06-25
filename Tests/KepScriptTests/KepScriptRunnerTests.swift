import XCTest
import KepModel
@testable import KepScript

final class KepScriptRunnerTests: XCTestCase {

    func testReturnsStringOutput() {
        let r = KepScriptRunner.run("return 1 + 2", on: MindMap(root: Topic(text: "R")))
        XCTAssertNil(r.error)
        XCTAssertEqual(r.output, "3")
        XCTAssertTrue(r.ok)
    }

    func testStringResult() {
        let r = KepScriptRunner.run("return 'hi ' .. 'there'", on: MindMap(root: Topic(text: "R")))
        XCTAssertEqual(r.output, "hi there")
    }

    func testErrorIsCaptured() {
        let r = KepScriptRunner.run("this is not lua !!", on: MindMap(root: Topic(text: "R")))
        XCTAssertFalse(r.ok)
        XCTAssertNotNil(r.error)
    }

    func testMutatesMap() {
        let map = MindMap(root: Topic(text: "R"))
        let r = KepScriptRunner.run("kep.addChild(kep.root(), 'X'); return 'ok'", on: map)
        XCTAssertEqual(r.output, "ok")
        XCTAssertEqual(map.root?.children.map(\.text), ["X"])
    }

    func testArrayResult() {
        let r = KepScriptRunner.run("return {1, 2, 3}", on: MindMap(root: Topic(text: "R")))
        XCTAssertEqual(r.output, "[1, 2, 3]")
    }
}
