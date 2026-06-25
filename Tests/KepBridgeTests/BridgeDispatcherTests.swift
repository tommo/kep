import XCTest
@testable import KepBridge

final class BridgeDispatcherTests: XCTestCase {

    private func dispatcher(calls: @escaping (String, String) -> String = { "\($0)(\($1))" }) -> BridgeDispatcher {
        BridgeDispatcher(
            listTools: { [BridgeToolDescriptor(name: "search", description: "Find things",
                                               parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"}}}"#)] },
            call: calls)
    }

    func testToolsListRoundTrips() {
        let line = dispatcher().handleLine(#"{"method":"tools/list"}"#)
        let resp = try! JSONDecoder().decode(BridgeResponse.self, from: line.data(using: .utf8)!)
        XCTAssertTrue(resp.ok)
        XCTAssertEqual(resp.tools?.first?.name, "search")
    }

    func testToolsCallRoutesNameAndArgs() {
        var captured: (String, String)?
        let d = dispatcher { name, args in captured = (name, args); return "ok:\(name)" }
        let line = d.handleLine(#"{"method":"tools/call","name":"search","arguments":"{\"query\":\"hi\"}"}"#)
        let resp = try! JSONDecoder().decode(BridgeResponse.self, from: line.data(using: .utf8)!)
        XCTAssertEqual(captured?.0, "search")
        XCTAssertEqual(captured?.1, #"{"query":"hi"}"#)
        XCTAssertEqual(resp.result, "ok:search")
    }

    func testCallMissingNameFails() {
        let line = dispatcher().handleLine(#"{"method":"tools/call"}"#)
        let resp = try! JSONDecoder().decode(BridgeResponse.self, from: line.data(using: .utf8)!)
        XCTAssertFalse(resp.ok)
        XCTAssertNotNil(resp.error)
    }

    func testUnknownMethodAndMalformed() {
        for bad in [#"{"method":"frobnicate"}"#, "not json at all"] {
            let resp = try! JSONDecoder().decode(
                BridgeResponse.self, from: dispatcher().handleLine(bad).data(using: .utf8)!)
            XCTAssertFalse(resp.ok)
        }
    }
}
