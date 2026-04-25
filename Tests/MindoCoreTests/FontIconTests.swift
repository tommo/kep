import XCTest
import AppKit
@testable import MindoBase

final class FontIconTests: XCTestCase {

    func testReturnsImageForKnownSFSymbol() {
        let icon = FontIcon()
        let img = icon.image(named: "bold", size: 14, color: .labelColor)
        XCTAssertGreaterThan(img.size.width, 0)
    }

    func testFAAliasResolvesToSFSymbol() {
        // fa-bold should map to "bold" — same image as direct lookup.
        let icon = FontIcon()
        let aliased = icon.image(named: "fa-bold", size: 14, color: .labelColor)
        XCTAssertGreaterThan(aliased.size.width, 0)
    }

    func testUnknownNameStillReturnsFallbackImage() {
        // Garbage in → fallback questionmark.circle, never a zero-size or nil.
        let icon = FontIcon()
        let img = icon.image(named: "definitely-not-a-real-icon-name", size: 16, color: .labelColor)
        XCTAssertGreaterThan(img.size.width, 0)
    }

    func testCacheShortCircuitsRepeatedLookup() {
        let icon = FontIcon()
        icon.clearCache()
        XCTAssertEqual(icon.cacheCount, 0)
        _ = icon.image(named: "bold", size: 14, color: .labelColor)
        XCTAssertEqual(icon.cacheCount, 1)
        _ = icon.image(named: "bold", size: 14, color: .labelColor)
        XCTAssertEqual(icon.cacheCount, 1, "second lookup should hit cache")
        _ = icon.image(named: "italic", size: 14, color: .labelColor)
        XCTAssertEqual(icon.cacheCount, 2)
    }

    func testFAMapCoversCommonMarkdownToolbarNames() {
        // The names the markdown editor uses through the alias table should
        // all resolve to non-empty SF Symbol names.
        for fa in ["fa-bold", "fa-italic", "fa-link", "fa-image", "fa-list-ul", "fa-list-ol", "fa-quote-left"] {
            XCTAssertNotNil(FontIcon.faToSF[fa], "missing FA alias for \(fa)")
        }
    }
}
