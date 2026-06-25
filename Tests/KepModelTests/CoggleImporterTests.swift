import XCTest
@testable import KepModel

final class CoggleImporterTests: XCTestCase {

    func testStructuralImportWorksLikeFreemind() throws {
        let xml = #"""
        <map version="1.0.1">
          <node TEXT="Root">
            <node TEXT="A"/>
            <node TEXT="B"><node TEXT="B1"/></node>
          </node>
        </map>
        """#
        let map = try CoggleImporter.parse(xml)
        XCTAssertEqual(map.root?.text, "Root")
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B"])
    }

    func testMarkdownLinkInTopicTextBecomesExtraLink() throws {
        let xml = #"""
        <map>
          <node TEXT="Visit [Google](https://google.com)"/>
        </map>
        """#
        let map = try CoggleImporter.parse(xml)
        XCTAssertEqual(map.root?.text, "Visit Google")
        XCTAssertEqual((map.root?.extra(.link) as? ExtraLink)?.uri, "https://google.com")
    }

    func testDataUrlImageBecomesMmdImageAttribute() throws {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII="
        let xml = "<map><node TEXT=\"![](data:image/png;base64,\(base64))\"/></map>"
        let map = try CoggleImporter.parse(xml)
        XCTAssertEqual(map.root?.attribute(TopicAttribute.image), base64)
        XCTAssertEqual(map.root?.text, "")
    }

    func testRemoteImageUrlAttachesAsLinkNotImage() throws {
        // External http(s) image URLs aren't fetched — recorded as a link
        // and stripped from text. Avoids hidden network calls during import.
        let xml = #"""
        <map><node TEXT="![logo](https://example.com/logo.png)"/></map>
        """#
        let map = try CoggleImporter.parse(xml)
        XCTAssertEqual(map.root?.text, "logo")
        XCTAssertEqual((map.root?.extra(.link) as? ExtraLink)?.uri, "https://example.com/logo.png")
    }

    func testPlainTextStaysUnmodified() throws {
        let xml = #"""
        <map><node TEXT="Plain text here"/></map>
        """#
        let map = try CoggleImporter.parse(xml)
        XCTAssertEqual(map.root?.text, "Plain text here")
        XCTAssertNil(map.root?.extra(.link))
    }

    func testExclamationLinkIsImageNotLink() {
        // The link regex must not match `![alt](url)` — that's an image.
        let result = CoggleImporter.firstLinkMatch(in: "![logo](https://x)")
        XCTAssertNil(result)
    }

    func testInvalidXMLPropagatesAsImportError() {
        XCTAssertThrowsError(try CoggleImporter.parse("<map>broken")) { error in
            guard case CoggleImporter.ImportError.invalidXML = error else {
                XCTFail("expected .invalidXML, got \(error)")
                return
            }
        }
    }

    func testNoRootNodeThrows() {
        XCTAssertThrowsError(try CoggleImporter.parse("<map></map>")) { error in
            guard case CoggleImporter.ImportError.noRootNode = error else {
                XCTFail("expected .noRootNode, got \(error)")
                return
            }
        }
    }
}
