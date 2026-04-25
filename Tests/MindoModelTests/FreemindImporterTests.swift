import XCTest
@testable import MindoModel

final class FreemindImporterTests: XCTestCase {

    func testParsesSimpleNodeTree() throws {
        let xml = """
        <map version="1.0.1">
          <node TEXT="Root">
            <node TEXT="Child A">
              <node TEXT="Leaf 1"/>
              <node TEXT="Leaf 2"/>
            </node>
            <node TEXT="Child B"/>
          </node>
        </map>
        """
        let map = try FreemindImporter.parse(xml)
        XCTAssertEqual(map.root?.text, "Root")
        XCTAssertEqual(map.root?.children.count, 2)
        XCTAssertEqual(map.root?.children[0].text, "Child A")
        XCTAssertEqual(map.root?.children[0].children.count, 2)
        XCTAssertEqual(map.root?.children[0].children[0].text, "Leaf 1")
        XCTAssertEqual(map.root?.children[1].text, "Child B")
    }

    func testTranslatesFoldedAndPositionAttributes() throws {
        let xml = """
        <map>
          <node TEXT="Root">
            <node TEXT="Folded subtree" FOLDED="true">
              <node TEXT="hidden"/>
            </node>
            <node TEXT="Left side" POSITION="left"/>
          </node>
        </map>
        """
        let map = try FreemindImporter.parse(xml)
        let folded = map.root?.children[0]
        XCTAssertEqual(folded?.attribute(TopicAttribute.collapsed), "true")
        let left = map.root?.children[1]
        XCTAssertEqual(left?.attribute(TopicAttribute.leftSide), "true")
    }

    func testRichContentReplacesText() throws {
        // Freeplane uses richcontent in place of TEXT for HTML-formatted titles.
        let xml = """
        <map>
          <node>
            <richcontent TYPE="NODE"><html><body><p>Bold <b>title</b></p></body></html></richcontent>
          </node>
        </map>
        """
        let map = try FreemindImporter.parse(xml)
        XCTAssertEqual(map.root?.text, "Bold title")
    }

    func testCapturesEdgeColorStyleAndWidth() throws {
        let xml = """
        <map>
          <node TEXT="Root">
            <node TEXT="Styled">
              <edge COLOR="#990000" STYLE="bezier" WIDTH="thin"/>
            </node>
            <node TEXT="Plain"/>
          </node>
        </map>
        """
        let map = try FreemindImporter.parse(xml)
        let styled = map.root?.children[0]
        XCTAssertEqual(styled?.attribute(TopicAttribute.edgeColor), "#990000")
        XCTAssertEqual(styled?.attribute(TopicAttribute.edgeStyle), "bezier")
        XCTAssertEqual(styled?.attribute(TopicAttribute.edgeWidth), "thin")
        let plain = map.root?.children[1]
        XCTAssertNil(plain?.attribute(TopicAttribute.edgeColor))
    }

    func testCapturesBuiltInIconAsEmoticon() throws {
        let xml = """
        <map>
          <node TEXT="Root">
            <node TEXT="Important">
              <icon BUILTIN="bell"/>
            </node>
          </node>
        </map>
        """
        let map = try FreemindImporter.parse(xml)
        let topic = map.root?.children[0]
        XCTAssertEqual(topic?.attribute(TopicAttribute.emoticon), "bell")
    }

    func testRoundTripsThroughMmdSerializer() throws {
        let xml = """
        <map>
          <node TEXT="Project">
            <node TEXT="Goals"><node TEXT="Q1"/></node>
            <node TEXT="Risks"/>
          </node>
        </map>
        """
        let imported = try FreemindImporter.parse(xml)
        let serialized = imported.write()
        let reparsed = try MindMap(text: serialized)
        XCTAssertEqual(reparsed.root?.text, "Project")
        XCTAssertEqual(reparsed.root?.children.map(\.text), ["Goals", "Risks"])
    }

    func testRejectsInvalidXML() {
        XCTAssertThrowsError(try FreemindImporter.parse("<map><node TEXT=\"x\"></map>"))
    }

    func testThrowsWhenNoRootNode() {
        XCTAssertThrowsError(try FreemindImporter.parse("<map></map>")) { error in
            guard case FreemindImporter.ImportError.noRootNode = error else {
                XCTFail("expected .noRootNode, got \(error)")
                return
            }
        }
    }
}
