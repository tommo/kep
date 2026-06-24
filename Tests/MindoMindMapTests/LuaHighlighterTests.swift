import XCTest
import AppKit
@testable import MindoBase

final class LuaHighlighterTests: XCTestCase {

    func testColorsKeywordsStringsAndComments() {
        let src = #"local x = "hi" -- a note"#
        let storage = NSTextStorage(string: src)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        LuaHighlighter.apply(to: storage, dark: false, font: font)
        let p = SyntaxPalette.resolved(dark: false)
        let ns = src as NSString

        func color(at sub: String) -> NSColor? {
            storage.attribute(.foregroundColor, at: ns.range(of: sub).location,
                              effectiveRange: nil) as? NSColor
        }
        XCTAssertEqual(color(at: "local"), p.keyword)
        XCTAssertEqual(color(at: "\"hi\""), p.string)
        // Comments are dimmed (alpha 0.5) so code reads first — same hue as the
        // palette comment color.
        XCTAssertEqual(color(at: "-- a note"), p.comment.withAlphaComponent(0.5))
        // Every glyph keeps the monospaced font.
        XCTAssertEqual(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, font)
    }

    func testEmptyIsNoOp() {
        let storage = NSTextStorage(string: "")
        LuaHighlighter.apply(to: storage, dark: true, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
        XCTAssertEqual(storage.length, 0)
    }
}
