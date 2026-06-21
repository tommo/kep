import XCTest
import AppKit
@testable import MindoMindMap

final class MindMapEmoticonPickerTests: XCTestCase {

    func testPickerItemsAreNonEmpty() {
        XCTAssertFalse(MindMapEmoticon.pickerItems.isEmpty)
    }

    func testPickerItemsAreSortedByName() {
        let names = MindMapEmoticon.pickerItems.map { $0.name }
        XCTAssertEqual(names, names.sorted())
    }

    func testNoPickerItemUsesTheGenericFallback() {
        // pickerItems are the explicit map entries; resolving each name must
        // return its own symbol, never the "tag" unknown-name fallback.
        for item in MindMapEmoticon.pickerItems {
            XCTAssertEqual(MindMapEmoticon.sfSymbolName(for: item.name), item.symbol)
            // (a couple entries legitimately map to a "tag.fill"-style symbol;
            // the fallback is the bare "tag", which must not appear here.)
            XCTAssertNotEqual(item.symbol, "tag")
        }
    }

    func testEveryPickerSymbolResolvesToARealSystemImage() {
        for item in MindMapEmoticon.pickerItems {
            XCTAssertNotNil(
                NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil),
                "\(item.name) → \(item.symbol) is not a valid SF Symbol"
            )
        }
    }

    func testPickerItemsMatchSuggestedNames() {
        XCTAssertEqual(MindMapEmoticon.pickerItems.map { $0.name },
                       MindMapEmoticon.suggestedNames)
    }
}
