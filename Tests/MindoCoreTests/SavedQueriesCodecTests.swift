import XCTest
@testable import MindoCore

final class SavedQueriesCodecTests: XCTestCase {
    func testRoundTrip() {
        let list = [SavedQuery(name: "Urgent", query: "#urgent"),
                    SavedQuery(name: "Todo", query: "done:false")]
        XCTAssertEqual(SavedQueriesCodec.decode(SavedQueriesCodec.encode(list)), list)
    }

    func testDecodeNilOrGarbageIsEmpty() {
        XCTAssertTrue(SavedQueriesCodec.decode(nil).isEmpty)
        XCTAssertTrue(SavedQueriesCodec.decode(Data("not json".utf8)).isEmpty)
    }

    func testUpsertAppendsThenReplacesByName() {
        var list = SavedQueriesCodec.upserting(SavedQuery(name: "A", query: "x"), into: [])
        XCTAssertEqual(list.count, 1)
        list = SavedQueriesCodec.upserting(SavedQuery(name: "B", query: "y"), into: list)
        XCTAssertEqual(list.map(\.name), ["A", "B"])
        list = SavedQueriesCodec.upserting(SavedQuery(name: "A", query: "z"), into: list)  // replace
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first { $0.name == "A" }?.query, "z")
    }
}
