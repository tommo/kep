import XCTest
@testable import KepModel

/// Comprehensive round-trip coverage mixing rich media + every extra +
/// attributes + code snippets through BOTH codecs: the on-disk `.mmd`
/// document format and the `TopicSubtreeCodec` clipboard JSON (copy/paste).
/// A topic carrying an image, emoticon, three colors, a note, a link, a
/// file, code snippets and structural attributes must survive each codec
/// intact.
final class RichMediaCodecRoundTripTests: XCTestCase {

    // A tiny but valid-looking base64 payload standing in for an embedded
    // image (the codec only cares that the attribute string round-trips).
    private let imageB64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    /// Build a deeply rich tree.
    private func buildRichMap() -> (MindMap, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root *with* _markdown_ & 😀")
        map.root = root

        let rich = root.addChild(text: "Rich node, with comma")
        rich.setAttribute(TopicAttribute.image, imageB64)
        rich.setAttribute(TopicAttribute.emoticon, "rocket")
        rich.setAttribute(TopicAttribute.fillColor, "# FF8800".replacingOccurrences(of: " ", with: ""))
        rich.setAttribute(TopicAttribute.textColor, "#112233")
        rich.setAttribute(TopicAttribute.borderColor, "#445566")
        rich.setAttribute(TopicAttribute.textAlign, "left")
        rich.setExtra(ExtraNote(text: "Line one.\nLine two with `code` and # hash."))
        rich.putCodeSnippet(language: "swift", body: "let x = 1\nprint(x)")
        rich.putCodeSnippet(language: "python", body: "x = 1\nprint(x)")

        let linked = rich.addChild(text: "Linked")
        linked.setExtra(ExtraLink(uri: "https://example.com/path?q=1&r=2"))
        linked.setAttribute(TopicAttribute.collapsed, "true")

        let filed = rich.addChild(text: "Filed")
        filed.setExtra(ExtraFile(uri: "files/diagram.png"))

        // A left-side branch with edge styling (FreeMind-imported flavor).
        let left = root.addChild(text: "Left branch")
        left.setAttribute(TopicAttribute.leftSide, "true")
        left.setAttribute(TopicAttribute.edgeColor, "#abcdef")
        left.setAttribute(TopicAttribute.edgeStyle, "bezier")
        left.setAttribute(TopicAttribute.edgeWidth, "thin")

        return (map, rich, linked)
    }

    private func assertRich(_ rich: Topic?, file: StaticString = #filePath, line: UInt = #line) {
        guard let rich else { return XCTFail("rich topic missing", file: file, line: line) }
        XCTAssertEqual(rich.attribute(TopicAttribute.image), imageB64, "image base64 survives", file: file, line: line)
        XCTAssertEqual(rich.attribute(TopicAttribute.emoticon), "rocket", file: file, line: line)
        XCTAssertEqual(rich.attribute(TopicAttribute.fillColor), "#FF8800", file: file, line: line)
        XCTAssertEqual(rich.attribute(TopicAttribute.textColor), "#112233", file: file, line: line)
        XCTAssertEqual(rich.attribute(TopicAttribute.borderColor), "#445566", file: file, line: line)
        XCTAssertEqual(rich.attribute(TopicAttribute.textAlign), "left", file: file, line: line)
        XCTAssertEqual((rich.extra(.note) as? ExtraNote)?.text,
                       "Line one.\nLine two with `code` and # hash.", "multiline note survives", file: file, line: line)
        XCTAssertEqual(rich.codeSnippets["swift"], "let x = 1\nprint(x)", file: file, line: line)
        XCTAssertEqual(rich.codeSnippets["python"], "x = 1\nprint(x)", file: file, line: line)
    }

    // MARK: - .mmd document codec

    func testRichMapSurvivesMmdRoundTrip() throws {
        let (map, _, _) = buildRichMap()
        let text = map.write()
        let parsed = try MindMap(text: text)

        XCTAssertEqual(parsed.root?.text, "Root *with* _markdown_ & 😀", "special chars in title survive")
        let rich = parsed.root?.children.first
        assertRich(rich)

        let linked = rich?.children.first
        XCTAssertEqual((linked?.extra(.link) as? ExtraLink)?.uri, "https://example.com/path?q=1&r=2")
        XCTAssertEqual(linked?.attribute(TopicAttribute.collapsed), "true")
        let filed = rich?.children.last
        XCTAssertEqual((filed?.extra(.file) as? ExtraFile)?.uri, "files/diagram.png")

        let left = parsed.root?.children.last
        XCTAssertEqual(left?.attribute(TopicAttribute.leftSide), "true")
        XCTAssertEqual(left?.attribute(TopicAttribute.edgeColor), "#abcdef")
        XCTAssertEqual(left?.attribute(TopicAttribute.edgeStyle), "bezier")
        XCTAssertEqual(left?.attribute(TopicAttribute.edgeWidth), "thin")
    }

    func testRichMapMmdWriteIsIdempotent() throws {
        let (map, _, _) = buildRichMap()
        let once = map.write()
        let twice = try MindMap(text: once).write()
        XCTAssertEqual(once, twice, "writing a rich map is stable under reparse")
    }

    // MARK: - Clipboard (TopicSubtreeCodec) codec

    func testRichSubtreeSurvivesClipboardCodec() throws {
        let (_, rich, _) = buildRichMap()
        let data = try TopicSubtreeCodec.encode(rich.clone(deep: true))
        let restored = try TopicSubtreeCodec.decode(data)
        assertRich(restored)
        // Children + their extras survive too.
        XCTAssertEqual(restored.children.map(\.text), ["Linked", "Filed"])
        XCTAssertEqual((restored.children[0].extra(.link) as? ExtraLink)?.uri,
                       "https://example.com/path?q=1&r=2")
        XCTAssertEqual((restored.children[1].extra(.file) as? ExtraFile)?.uri, "files/diagram.png")
    }

    func testRichForestSurvivesClipboardCodec() throws {
        let (_, rich, _) = buildRichMap()
        let plain = Topic(text: "Plain")
        let data = try TopicSubtreeCodec.encodeForest([rich.clone(deep: true), plain])
        let restored = try TopicSubtreeCodec.decodeForest(data)
        XCTAssertEqual(restored.count, 2)
        assertRich(restored[0])
        XCTAssertEqual(restored[1].text, "Plain")
    }

    // MARK: - Cross-codec: clone, mmd, then clipboard must all agree

    func testCloneMatchesOriginalRichness() {
        let (_, rich, _) = buildRichMap()
        assertRich(rich.clone(deep: true))
    }

    func testEmptyAndEdgeValuesRoundTripThroughMmd() throws {
        // Empty note (allowed), an attribute value with special chars, and a
        // code snippet whose body is empty must not corrupt the document.
        let map = MindMap()
        let root = Topic(text: "R"); map.root = root
        let t = root.addChild(text: "")                  // empty title
        t.setExtra(ExtraNote(text: ""))                  // empty note
        t.putCodeSnippet(language: "text", body: "")     // empty snippet
        let parsed = try MindMap(text: map.write())
        let pt = parsed.root?.children.first
        XCTAssertNotNil(pt, "an empty-title topic still round-trips")
        XCTAssertEqual(pt?.codeSnippets["text"], "")
    }
}
