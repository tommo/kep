import XCTest
import AppKit
@testable import MindoBase

final class EditorThemePresetsTests: XCTestCase {
    func testEveryPresetIsEnabledWithUniqueID() {
        XCTAssertFalse(EditorThemePresets.all.isEmpty)
        XCTAssertTrue(EditorThemePresets.all.allSatisfy { $0.theme.enabled }, "a preset must enable custom colors")
        let ids = EditorThemePresets.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "preset ids must be unique")
    }

    func testEveryRoleHasAValidHexInBothModes() {
        func check(_ colors: EditorThemeColors, _ name: String) {
            let hexes = [colors.text, colors.keyword, colors.string,
                         colors.comment, colors.link, colors.punctuation]
            for hex in hexes {
                guard let hex else { XCTFail("\(name): a role is unspecified"); continue }
                XCTAssertNotNil(NSColor(hexString: hex), "\(name): invalid hex \(hex)")
            }
        }
        for preset in EditorThemePresets.all {
            check(preset.theme.light, "\(preset.name) light")
            check(preset.theme.dark, "\(preset.name) dark")
        }
    }
}
