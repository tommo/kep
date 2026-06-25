import XCTest
@testable import KepModel

final class FreemindExporterTests: XCTestCase {

    func testExportsRootAndChildren() {
        let map = MindMap()
        let root = Topic(text: "Project")
        map.root = root
        let goals = root.addChild(text: "Goals")
        _ = goals.addChild(text: "Q1")
        _ = root.addChild(text: "Risks")

        let xml = FreemindExporter.export(map)
        XCTAssertTrue(xml.contains("<?xml"))
        XCTAssertTrue(xml.contains("<map"))
        XCTAssertTrue(xml.contains("TEXT=\"Project\""))
        XCTAssertTrue(xml.contains("TEXT=\"Goals\""))
        XCTAssertTrue(xml.contains("TEXT=\"Q1\""))
        XCTAssertTrue(xml.contains("TEXT=\"Risks\""))
    }

    func testFoldedAndPositionAttributesPreserved() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let folded = root.addChild(text: "F")
        folded.setAttribute(TopicAttribute.collapsed, "true")
        let left = root.addChild(text: "L")
        left.setAttribute(TopicAttribute.leftSide, "true")

        let xml = FreemindExporter.export(map)
        XCTAssertTrue(xml.contains("FOLDED=\"true\""))
        XCTAssertTrue(xml.contains("POSITION=\"left\""))
    }

    func testEdgeAttributesAndIconWritten() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let styled = root.addChild(text: "Styled")
        styled.setAttribute(TopicAttribute.edgeColor, "#990000")
        styled.setAttribute(TopicAttribute.edgeStyle, "bezier")
        styled.setAttribute(TopicAttribute.edgeWidth, "thin")
        styled.setAttribute(TopicAttribute.emoticon, "bell")

        let xml = FreemindExporter.export(map)
        XCTAssertTrue(xml.contains("<edge COLOR=\"#990000\" STYLE=\"bezier\" WIDTH=\"thin\"/>"))
        XCTAssertTrue(xml.contains("<icon BUILTIN=\"bell\"/>"))
    }

    func testEscapesAttributeValueSpecialChars() {
        let map = MindMap()
        let root = Topic(text: "A & <b> \"q\" 'apos")
        map.root = root
        let xml = FreemindExporter.export(map)
        XCTAssertTrue(xml.contains("TEXT=\"A &amp; &lt;b&gt; &quot;q&quot; &apos;apos\""))
    }

    /// import → export → import preserves text, structure, side, fold, edge,
    /// and icon attrs.
    func testFullRoundTripPreservesEverything() throws {
        let original = """
        <map version="1.0.1">
          <node TEXT="Root">
            <node TEXT="A" FOLDED="true">
              <edge COLOR="#990000" STYLE="bezier" WIDTH="thin"/>
              <icon BUILTIN="bell"/>
              <node TEXT="A1"/>
            </node>
            <node TEXT="B" POSITION="left"/>
          </node>
        </map>
        """
        let imported = try FreemindImporter.parse(original)
        let exported = FreemindExporter.export(imported)
        let reimported = try FreemindImporter.parse(exported)

        XCTAssertEqual(reimported.root?.text, "Root")
        let a = reimported.root?.children[0]
        XCTAssertEqual(a?.text, "A")
        XCTAssertEqual(a?.attribute(TopicAttribute.collapsed), "true")
        XCTAssertEqual(a?.attribute(TopicAttribute.edgeColor), "#990000")
        XCTAssertEqual(a?.attribute(TopicAttribute.edgeStyle), "bezier")
        XCTAssertEqual(a?.attribute(TopicAttribute.edgeWidth), "thin")
        XCTAssertEqual(a?.attribute(TopicAttribute.emoticon), "bell")
        XCTAssertEqual(a?.children.first?.text, "A1")
        let b = reimported.root?.children[1]
        XCTAssertEqual(b?.attribute(TopicAttribute.leftSide), "true")
    }
}
