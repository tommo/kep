import XCTest
@testable import MindoMarkdown

final class MarkdownDropFormatterTests: XCTestCase {

    func testImageURLBecomesMarkdownImageLink() {
        let url = URL(fileURLWithPath: "/tmp/diagram.png")
        XCTAssertEqual(MarkdownDropFormatter.snippet(for: url), "![diagram](/tmp/diagram.png)")
    }

    func testImageExtensionsAreCaseInsensitive() {
        let url = URL(fileURLWithPath: "/tmp/PHOTO.JPG")
        // The alt is the bare stem (case preserved); the extension match itself is lower-cased.
        XCTAssertEqual(MarkdownDropFormatter.snippet(for: url), "![PHOTO](/tmp/PHOTO.JPG)")
    }

    func testSpaceInPathIsURLEncoded() {
        let url = URL(fileURLWithPath: "/tmp/my image.png")
        XCTAssertEqual(MarkdownDropFormatter.snippet(for: url), "![my image](/tmp/my%20image.png)")
    }

    func testUnknownExtensionFallsThroughAsNil() {
        let url = URL(fileURLWithPath: "/tmp/binary.bin")
        XCTAssertNil(MarkdownDropFormatter.snippet(for: url))
    }

    func testTextFileBecomesFencedCodeBlock() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).swift")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "let x = 1\n".write(to: tmp, atomically: true, encoding: .utf8)
        let snippet = MarkdownDropFormatter.snippet(for: tmp)
        XCTAssertEqual(snippet, "```swift\nlet x = 1\n```")
    }

    func testMarkdownFileGetsBlankLanguageLabel() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).md")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "# Hi\n".write(to: tmp, atomically: true, encoding: .utf8)
        let snippet = MarkdownDropFormatter.snippet(for: tmp)
        // "md" language tag would render the dropped file's source as itself —
        // not what the user wants. Plain ``` keeps the snippet legible.
        XCTAssertEqual(snippet, "```\n# Hi\n```")
    }

    func testMultipleURLsJoinedWithBlankLine() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.png"),
            URL(fileURLWithPath: "/tmp/b.png"),
        ]
        XCTAssertEqual(
            MarkdownDropFormatter.snippet(for: urls),
            "![a](/tmp/a.png)\n\n![b](/tmp/b.png)"
        )
    }

    func testBracketsInAltTextAreEscaped() {
        // Markdown alt-text can't contain raw [ ]; the formatter escapes both.
        XCTAssertEqual(MarkdownDropFormatter.escapeAlt("a[b]c"), "a\\[b\\]c")
    }

    func testParensInPathAreURLEscaped() {
        // Naked ( or ) in the URL part of a markdown link end the link early.
        let url = URL(fileURLWithPath: "/tmp/file (final).png")
        XCTAssertEqual(MarkdownDropFormatter.snippet(for: url),
                       "![file (final)](/tmp/file%20%28final%29.png)")
    }
}
