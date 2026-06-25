import XCTest
@testable import KepModel

/// FreeMind is bidirectional, so a build → export(.mm) → import round-trip
/// must preserve everything the format supports: structure, XML-dangerous
/// text, folded/position flags, edge styling, and BUILTIN icons. Notes /
/// links / node colors aren't part of the FreeMind export and are out of
/// scope here.
final class FreemindRoundTripTests: XCTestCase {

    private func roundTrip(_ map: MindMap) throws -> MindMap {
        try FreemindImporter.parse(FreemindExporter.export(map))
    }

    func testStructureAndTextWithXMLSpecialCharsSurvive() throws {
        let map = MindMap()
        let root = Topic(text: "A & B <tag> \"q\" 'apos'")
        map.root = root
        let child = root.addChild(text: "child > 5 && x<10")
        _ = child.addChild(text: "leaf")
        _ = root.addChild(text: "second")

        let parsed = try roundTrip(map)
        XCTAssertEqual(parsed.root?.text, "A & B <tag> \"q\" 'apos'",
                       "XML special chars round-trip through escape/unescape")
        XCTAssertEqual(parsed.root?.children.map(\.text), ["child > 5 && x<10", "second"])
        XCTAssertEqual(parsed.root?.children.first?.children.first?.text, "leaf",
                       "nesting depth preserved")
    }

    func testFoldedAndPositionSurvive() throws {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let folded = root.addChild(text: "Folded"); folded.setAttribute(TopicAttribute.collapsed, "true")
        _ = folded.addChild(text: "hidden child")     // gives Folded children so it isn't self-closed
        let left = root.addChild(text: "Left"); left.setAttribute(TopicAttribute.leftSide, "true")

        let parsed = try roundTrip(map)
        let pFolded = parsed.root?.children.first { $0.text == "Folded" }
        let pLeft = parsed.root?.children.first { $0.text == "Left" }
        XCTAssertEqual(pFolded?.attribute(TopicAttribute.collapsed), "true", "FOLDED → collapsed")
        XCTAssertEqual(pLeft?.attribute(TopicAttribute.leftSide), "true", "POSITION=left → leftSide")
    }

    func testEdgeAttributesAndIconSurvive() throws {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let styled = root.addChild(text: "Styled")
        styled.setAttribute(TopicAttribute.edgeColor, "#ff0000")
        styled.setAttribute(TopicAttribute.edgeStyle, "bezier")
        styled.setAttribute(TopicAttribute.edgeWidth, "2")
        styled.setAttribute(TopicAttribute.emoticon, "idea")

        let parsed = try roundTrip(map)
        let s = parsed.root?.children.first
        XCTAssertEqual(s?.attribute(TopicAttribute.edgeColor), "#ff0000")
        XCTAssertEqual(s?.attribute(TopicAttribute.edgeStyle), "bezier")
        XCTAssertEqual(s?.attribute(TopicAttribute.edgeWidth), "2")
        XCTAssertEqual(s?.attribute(TopicAttribute.emoticon), "idea", "BUILTIN icon → emoticon")
    }

    func testDeepWideTreeStructurePreserved() throws {
        let map = MindMap()
        let root = Topic(text: "R"); map.root = root
        for i in 0..<5 {
            let branch = root.addChild(text: "B\(i)")
            for j in 0..<3 { _ = branch.addChild(text: "B\(i)-\(j)") }
        }
        let parsed = try roundTrip(map)
        XCTAssertEqual(parsed.root?.children.count, 5)
        XCTAssertEqual(parsed.root?.subtreeCount(), map.root?.subtreeCount(), "same total node count")
        XCTAssertEqual(parsed.root?.children.map { $0.children.count }, [3, 3, 3, 3, 3])
    }

    func testExportIsValidParseableXMLTwice() throws {
        // Export → import → export → import must be stable (idempotent shape).
        let map = MindMap()
        let root = Topic(text: "Stable & <ok>"); map.root = root
        _ = root.addChild(text: "x")
        let once = try roundTrip(map)
        let twice = try roundTrip(once)
        XCTAssertEqual(once.root?.text, twice.root?.text)
        XCTAssertEqual(once.root?.subtreeCount(), twice.root?.subtreeCount())
    }
}
