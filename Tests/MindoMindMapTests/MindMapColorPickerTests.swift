import XCTest
import AppKit
@testable import MindoMindMap

final class MindMapColorPickerTests: XCTestCase {

    // MARK: - seedColor

    func testSeedUsesParsedCurrentColor() {
        let seed = MindMapColorPicker.seedColor(currentAttribute: "#FF0000", fallback: .black)
        let rgb = seed.usingColorSpace(.sRGB)!
        XCTAssertEqual(rgb.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgb.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb.blueComponent, 0.0, accuracy: 0.01)
    }

    func testSeedFallsBackWhenAttributeMissing() {
        let seed = MindMapColorPicker.seedColor(currentAttribute: nil, fallback: .blue)
        XCTAssertEqual(seed, .blue)
    }

    func testSeedFallsBackWhenAttributeUnparseable() {
        let seed = MindMapColorPicker.seedColor(currentAttribute: "not-a-color", fallback: .green)
        XCTAssertEqual(seed, .green)
    }

    // MARK: - result mapping

    func testOKButtonPicksChosenColor() {
        let chosen = NSColor.orange
        XCTAssertEqual(
            MindMapColorPicker.result(for: .alertFirstButtonReturn, chosen: chosen),
            .pick(chosen))
    }

    func testClearButtonClears() {
        XCTAssertEqual(
            MindMapColorPicker.result(for: .alertSecondButtonReturn, chosen: .red),
            .clear)
    }

    func testCancelButtonCancels() {
        XCTAssertEqual(
            MindMapColorPicker.result(for: .alertThirdButtonReturn, chosen: .red),
            .cancelled)
    }

    // MARK: - round-trip through the on-disk form

    func testChosenColorRoundTripsToHex() {
        // The well hands back an NSColor; we persist via MindMapColor.write
        // and it must parse back to the same color (lossless w/ javamind).
        let chosen = NSColor(srgbRed: 0.29, green: 0.56, blue: 0.89, alpha: 1.0)
        let written = MindMapColor.write(chosen)
        let reparsed = MindMapColorPicker.seedColor(currentAttribute: written, fallback: .black)
            .usingColorSpace(.sRGB)!
        XCTAssertEqual(reparsed.redComponent, 0.29, accuracy: 0.01)
        XCTAssertEqual(reparsed.greenComponent, 0.56, accuracy: 0.01)
        XCTAssertEqual(reparsed.blueComponent, 0.89, accuracy: 0.01)
    }
}
