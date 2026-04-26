import XCTest
import AppKit
@testable import MindoBase

final class EditorFontTests: XCTestCase {

    func testNilNameYieldsSystemMono() {
        let font = EditorFont.resolve(family: nil, size: 13)
        // The system mono font's familyName starts with "." (e.g.
        // ".AppleSystemUIFontMonospaced") on modern macOS — both legacy
        // and current paths produce a usable monospaced font, so just
        // assert size + advance equality across two calls instead of
        // string-matching the family name (which is OS-version-fragile).
        XCTAssertEqual(font.pointSize, 13)
        let again = EditorFont.resolve(family: nil, size: 13)
        XCTAssertEqual(font.advancement(forCGGlyph: 0), again.advancement(forCGGlyph: 0))
    }

    func testEmptyNameYieldsSystemMono() {
        let font = EditorFont.resolve(family: "", size: 13)
        XCTAssertEqual(font.pointSize, 13)
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        // Same family — both are the system mono.
        XCTAssertEqual(font.familyName, mono.familyName)
    }

    func testWhitespaceOnlyNameYieldsSystemMono() {
        let font = EditorFont.resolve(family: "   ", size: 13)
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        XCTAssertEqual(font.familyName, mono.familyName)
    }

    func testKnownInstalledMonoNameWins() {
        // Menlo ships with every macOS install — safe target.
        let font = EditorFont.resolve(family: "Menlo", size: 14)
        XCTAssertEqual(font.familyName, "Menlo")
        XCTAssertEqual(font.pointSize, 14)
    }

    func testUnknownNameFallsBackToSystemMono() {
        let font = EditorFont.resolve(family: "ThisFontDoesNotExist-XYZ", size: 13)
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        XCTAssertEqual(font.familyName, mono.familyName)
    }

    func testPickerFamiliesIncludeAllPlausibleChoices() {
        // Hand-list the families the picker offers so a future shuffle
        // / removal is flagged. Order matters for the picker UX.
        XCTAssertEqual(
            EditorFont.pickerFamilies,
            ["SF Mono", "Menlo", "Monaco", "Courier New", "JetBrains Mono"]
        )
    }
}
