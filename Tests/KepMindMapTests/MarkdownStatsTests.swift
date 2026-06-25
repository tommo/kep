import XCTest
@testable import KepMarkdown

final class MarkdownStatsTests: XCTestCase {

    func testEmptyStringIsZeroes() {
        let s = MarkdownStats.compute("")
        XCTAssertEqual(s.words, 0)
        XCTAssertEqual(s.characters, 0)
    }

    func testSimpleSentence() {
        let s = MarkdownStats.compute("hello world")
        XCTAssertEqual(s.words, 2)
        XCTAssertEqual(s.characters, "hello world".count)
    }

    func testMultipleWhitespaceCollapses() {
        // Words split on any whitespace — runs of whitespace don't add
        // empty entries.
        let s = MarkdownStats.compute("hello   world\n\n   foo")
        XCTAssertEqual(s.words, 3)
    }

    func testNewlinesCountAsCharacters() {
        // "a\nb" is 3 grapheme clusters; words = 2.
        let s = MarkdownStats.compute("a\nb")
        XCTAssertEqual(s.words, 2)
        XCTAssertEqual(s.characters, 3)
    }

    func testEmojiCountsAsOneCharacter() {
        // Multi-scalar emoji (👨‍👩‍👧) is one grapheme cluster.
        let s = MarkdownStats.compute("hi 👨‍👩‍👧 bye")
        XCTAssertEqual(s.words, 3)
        XCTAssertEqual(s.characters, 8)  // h,i,space,emoji,space,b,y,e
    }

    func testWhitespaceOnlyHasZeroWords() {
        let s = MarkdownStats.compute("   \n\t  ")
        XCTAssertEqual(s.words, 0)
        XCTAssertEqual(s.characters, "   \n\t  ".count)
    }
}
