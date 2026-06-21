import XCTest
import AppKit
@testable import MindoBase

final class EditorThemeTests: XCTestCase {

    func testApplyingOverridesSelectedRolesOnly() {
        let base = SyntaxPalette.light
        let over = EditorThemeColors(keyword: "#FF0000")   // only keyword changed
        let p = base.applying(over)
        XCTAssertEqual(p.keyword.hexString, "#FF0000")
        XCTAssertEqual(p.text.hexString, base.text.hexString, "untouched roles keep base")
        XCTAssertEqual(p.string.hexString, base.string.hexString)
    }

    func testApplyingIgnoresMalformedHex() {
        let base = SyntaxPalette.dark
        let p = base.applying(EditorThemeColors(string: "not-a-color"))
        XCTAssertEqual(p.string.hexString, base.string.hexString)
    }

    func testEditorThemeCodableRoundTrip() throws {
        let theme = EditorTheme(enabled: true,
                                light: EditorThemeColors(keyword: "#123456"),
                                dark: EditorThemeColors(link: "#ABCDEF"))
        let data = try JSONEncoder().encode(theme)
        let back = try JSONDecoder().decode(EditorTheme.self, from: data)
        XCTAssertEqual(theme, back)
    }

    func testResolvedHonorsStoreWhenEnabled() {
        let key = "mindo.prefs.editorTheme"
        let prior = UserDefaults.standard.data(forKey: key)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        // Disabled (default) → base.
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(SyntaxPalette.resolved(dark: false).keyword.hexString,
                       SyntaxPalette.light.keyword.hexString)
        // Enabled with an override → applied.
        let theme = EditorTheme(enabled: true, light: EditorThemeColors(keyword: "#00FF00"))
        UserDefaults.standard.set(try! JSONEncoder().encode(theme), forKey: key)
        XCTAssertEqual(SyntaxPalette.resolved(dark: false).keyword.hexString, "#00FF00")
    }

    func testColorHexRoundTrip() {
        XCTAssertEqual(NSColor(hexString: "#1A2B3C")?.hexString, "#1A2B3C")
        XCTAssertNil(NSColor(hexString: "#XYZ"))
        XCTAssertNotNil(NSColor(hexString: "FFFFFF"))
    }
}
