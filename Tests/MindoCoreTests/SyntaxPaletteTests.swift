import XCTest
import AppKit
@testable import MindoBase

final class SyntaxPaletteTests: XCTestCase {

    func testResolvedPicksByAppearance() {
        XCTAssertEqual(SyntaxPalette.resolved(dark: false).text, SyntaxPalette.light.text)
        XCTAssertEqual(SyntaxPalette.resolved(dark: true).text, SyntaxPalette.dark.text)
    }

    func testLightAndDarkDiffer() {
        // Dark text should be lighter than light text (inverted backgrounds).
        XCTAssertGreaterThan(SyntaxPalette.dark.text.whiteComponentApprox,
                             SyntaxPalette.light.text.whiteComponentApprox)
    }

    func testAllRolesDistinctWithinAPalette() {
        let p = SyntaxPalette.light
        let roles = [p.text, p.keyword, p.string, p.comment, p.link, p.punctuation]
        // No two roles collapse to the same color (each is a meaningful token).
        for i in roles.indices {
            for j in (i + 1)..<roles.count {
                XCTAssertNotEqual(roles[i], roles[j], "roles \(i) and \(j) must differ")
            }
        }
    }
}

private extension NSColor {
    /// Rough perceptual lightness for an sRGB color (test helper).
    var whiteComponentApprox: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    }
}
