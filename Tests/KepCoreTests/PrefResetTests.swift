import XCTest
@testable import KepCore

final class PrefResetTests: XCTestCase {

    /// An isolated UserDefaults so the test never touches real app prefs.
    private func makeDefaults() -> UserDefaults {
        let suite = "PrefResetTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testEveryGroupHasKeys() {
        for group in PrefResetGroup.allCases {
            XCTAssertFalse(group.keys.isEmpty, "\(group) should own at least one key")
        }
    }

    func testGroupsAreDisjoint() {
        // No key may belong to two tabs — otherwise one tab's reset would
        // silently clobber another's setting.
        var seen: [String: PrefResetGroup] = [:]
        for group in PrefResetGroup.allCases {
            for key in group.keys {
                XCTAssertNil(seen[key], "\(key) is in both \(seen[key]!) and \(group)")
                seen[key] = group
            }
        }
    }

    func testResetRemovesOnlyThatGroupsKeys() {
        let d = makeDefaults()
        // Seed one key from each group with a non-default value.
        let general = PrefResetGroup.general.keys[0]
        let mindmap = PrefResetGroup.mindmap.keys[0]
        d.set("custom", forKey: general)
        d.set(999.0, forKey: mindmap)

        PrefReset.reset(.general, in: d)

        XCTAssertNil(d.object(forKey: general), "general key should be cleared")
        XCTAssertNotNil(d.object(forKey: mindmap), "mindmap key must survive a general reset")
    }

    func testResetClearsAllKeysInGroup() {
        let d = makeDefaults()
        for key in PrefResetGroup.editor.keys { d.set("x", forKey: key) }
        PrefReset.reset(.editor, in: d)
        for key in PrefResetGroup.editor.keys {
            XCTAssertNil(d.object(forKey: key), "\(key) should be cleared")
        }
    }

    func testKnownKeysAreCovered() {
        // Guard against a pref being added to the UI but forgotten here.
        let all = Set(PrefResetGroup.allCases.flatMap { $0.keys })
        XCTAssertTrue(all.contains(PrefKeys.theme))
        XCTAssertTrue(all.contains(PrefKeys.sidebarVisible))
        XCTAssertTrue(all.contains(PrefKeys.editorFontSize))
        XCTAssertTrue(all.contains(PrefKeys.mindmapConnectorStyle))
        XCTAssertTrue(all.contains(PrefKeys.aiStreamingEnabled))
    }
}
