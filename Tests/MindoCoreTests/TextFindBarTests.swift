import XCTest
import AppKit
@testable import MindoBase

final class TextFindBarTests: XCTestCase {

    /// The whole bug was a sender whose tag didn't match a real
    /// NSFindPanelAction. Guard our raw values against the AppKit enum so
    /// an SDK rename can't silently re-break ⌘F.
    func testActionRawValuesMatchAppKit() {
        XCTAssertEqual(TextFindBar.Action.showFindPanel.rawValue, Int(NSFindPanelAction.showFindPanel.rawValue))
        XCTAssertEqual(TextFindBar.Action.next.rawValue, Int(NSFindPanelAction.next.rawValue))
        XCTAssertEqual(TextFindBar.Action.previous.rawValue, Int(NSFindPanelAction.previous.rawValue))
        XCTAssertEqual(TextFindBar.Action.replaceAll.rawValue, Int(NSFindPanelAction.replaceAll.rawValue))
        XCTAssertEqual(TextFindBar.Action.replace.rawValue, Int(NSFindPanelAction.replace.rawValue))
        XCTAssertEqual(TextFindBar.Action.replaceAndFind.rawValue, Int(NSFindPanelAction.replaceAndFind.rawValue))
    }

    func testSenderCarriesTheActionTag() {
        // The fix: performFindPanelAction reads sender.tag — it must be the
        // action's raw value, NOT 0 (the old nil-sender bug).
        let item = TextFindBar.sender(for: .showFindPanel)
        XCTAssertEqual(item.tag, Int(NSFindPanelAction.showFindPanel.rawValue))
        XCTAssertNotEqual(item.tag, 0)
    }

    func testEachActionProducesMatchingSenderTag() {
        for action in [TextFindBar.Action.showFindPanel, .next, .previous,
                       .replaceAll, .replace, .replaceAndFind] {
            XCTAssertEqual(TextFindBar.sender(for: action).tag, action.rawValue)
        }
    }
}
