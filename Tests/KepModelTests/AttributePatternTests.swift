import XCTest
@testable import KepModel

final class AttributePatternTests: XCTestCase {

    func testSingleBacktickValue() {
        var map: [String: String] = [:]
        let ok = MindMap.fillMapByAttributes(line: "> __version__=`1.1`", into: &map)
        XCTAssertTrue(ok)
        XCTAssertEqual(map, ["__version__": "1.1"])
    }

    func testMultipleAttributesSeparatedByComma() {
        var map: [String: String] = [:]
        _ = MindMap.fillMapByAttributes(line: "> collapsed=`true`,mmd.emoticon=`star`", into: &map)
        XCTAssertEqual(map, ["collapsed": "true", "mmd.emoticon": "star"])
    }

    func testValueWithEmbeddedBackticksUsesLongerFence() {
        var map: [String: String] = [:]
        _ = MindMap.fillMapByAttributes(line: "> sample=``a `b` c``", into: &map)
        XCTAssertEqual(map["sample"], "a `b` c")
    }

    func testRoundTripSerialization() {
        let attrs = ["__version__": "1.1", "collapsed": "true", "mmd.emoticon": "star"]
        let line = "> " + MindMap.attributesAsString(attrs)
        var parsed: [String: String] = [:]
        _ = MindMap.fillMapByAttributes(line: line, into: &parsed)
        XCTAssertEqual(parsed, attrs)
    }
}
