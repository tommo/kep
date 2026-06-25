import XCTest
import AppKit
@testable import KepBase

final class FocusStyleTests: XCTestCase {
    func testFocusedColorIsUnchanged() {
        let c = NSColor.systemBlue
        XCTAssertEqual(FocusStyle.degraded(c, focused: true), c)
    }

    func testUnfocusedColorFadesAlpha() {
        let c = NSColor.systemBlue.withAlphaComponent(1.0)
        let faded = FocusStyle.degraded(c, focused: false)
        XCTAssertEqual(faded.alphaComponent, FocusStyle.unfocusedAlpha, accuracy: 0.001,
                       "an unfocused selection should fade to ~40% alpha")
    }

    func testUnfocusedScalesExistingAlpha() {
        // A colour that's already semi-transparent fades proportionally, not to
        // a flat value — so layered selections keep their relative weighting.
        let c = NSColor.systemBlue.withAlphaComponent(0.5)
        let faded = FocusStyle.degraded(c, focused: false)
        XCTAssertEqual(faded.alphaComponent, 0.5 * FocusStyle.unfocusedAlpha, accuracy: 0.001)
    }

    @MainActor func testIsFocusedFalseWithoutWindow() {
        // A view not in any window can't own focus.
        XCTAssertFalse(FocusStyle.isFocused(NSView(frame: .zero)))
    }
}
