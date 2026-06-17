import XCTest
import MindoModel
@testable import MindoScript

final class MindoScriptRunnerTests: XCTestCase {

    func testReturnsStringOutput() {
        let r = MindoScriptRunner.run("return 1 + 2", on: MindMap(root: Topic(text: "R")))
        XCTAssertNil(r.error)
        XCTAssertEqual(r.output, "3")
        XCTAssertTrue(r.ok)
    }

    func testStringResult() {
        let r = MindoScriptRunner.run("return 'hi ' .. 'there'", on: MindMap(root: Topic(text: "R")))
        XCTAssertEqual(r.output, "hi there")
    }

    func testErrorIsCaptured() {
        let r = MindoScriptRunner.run("this is not lua !!", on: MindMap(root: Topic(text: "R")))
        XCTAssertFalse(r.ok)
        XCTAssertNotNil(r.error)
    }

    func testMutatesMap() {
        let map = MindMap(root: Topic(text: "R"))
        let r = MindoScriptRunner.run("mindo.addChild(mindo.root(), 'X'); return 'ok'", on: map)
        XCTAssertEqual(r.output, "ok")
        XCTAssertEqual(map.root?.children.map(\.text), ["X"])
    }

    func testArrayResult() {
        let r = MindoScriptRunner.run("return {1, 2, 3}", on: MindMap(root: Topic(text: "R")))
        XCTAssertEqual(r.output, "[1, 2, 3]")
    }
}
