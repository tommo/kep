import XCTest
import AppKit
@testable import MindoBase

final class EditorFontTests: XCTestCase {

    func testBlankFamilyYieldsSystemMono() {
        // nil / empty / whitespace-only family all fall back to the system mono
        // at the requested size.
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        for family in [nil, "", "   "] as [String?] {
            let font = EditorFont.resolve(family: family, size: 13)
            XCTAssertEqual(font.pointSize, 13, "family=\(String(describing: family))")
            XCTAssertEqual(font.familyName, mono.familyName, "family=\(String(describing: family))")
        }
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
