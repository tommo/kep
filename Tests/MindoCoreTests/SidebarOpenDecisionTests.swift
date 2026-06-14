import XCTest
@testable import MindoCore

final class SidebarOpenDecisionTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/ws/a.md")
    private let b = URL(fileURLWithPath: "/ws/b.md")

    func testOpensFileWhenNoneActive() {
        XCTAssertTrue(SidebarOpenDecision.shouldOpen(isFile: true, selectedURL: a, activeURL: nil))
    }

    func testOpensDifferentFile() {
        XCTAssertTrue(SidebarOpenDecision.shouldOpen(isFile: true, selectedURL: b, activeURL: a))
    }

    func testDoesNotReopenActiveFile() {
        // The reverse active-doc→selection sync lands here; must not re-open.
        XCTAssertFalse(SidebarOpenDecision.shouldOpen(isFile: true, selectedURL: a, activeURL: a))
    }

    func testActiveComparisonIsPathNormalized() {
        // Same file, non-standardized path (trailing /./) must still match.
        let messy = URL(fileURLWithPath: "/ws/./a.md")
        XCTAssertFalse(SidebarOpenDecision.shouldOpen(isFile: true, selectedURL: messy, activeURL: a))
    }

    func testFolderNeverOpens() {
        let folder = URL(fileURLWithPath: "/ws/sub")
        XCTAssertFalse(SidebarOpenDecision.shouldOpen(isFile: false, selectedURL: folder, activeURL: nil))
    }

    func testNilSelectionNeverOpens() {
        XCTAssertFalse(SidebarOpenDecision.shouldOpen(isFile: true, selectedURL: nil, activeURL: a))
    }

    // MARK: - Input source (#21 / R6)

    func testKeyboardNavigationNeverOpens() {
        // Arrow-keying onto a perfectly openable file must only highlight it —
        // this is the #21 fix (no flood of opens while traversing a folder).
        XCTAssertFalse(SidebarOpenDecision.shouldOpen(
            isFile: true, selectedURL: b, activeURL: a, source: .keyboardNavigation))
    }

    func testPointerStillOpensByDefault() {
        // The default source keeps the original single-click-opens behaviour.
        XCTAssertTrue(SidebarOpenDecision.shouldOpen(
            isFile: true, selectedURL: b, activeURL: a, source: .pointer))
    }

    func testKeyboardConfirmOpensSelectedFile() {
        // Return on a highlighted file opens it (R6).
        XCTAssertTrue(SidebarOpenDecision.shouldOpen(
            isFile: true, selectedURL: b, activeURL: a, source: .keyboardConfirm))
    }

    func testKeyboardConfirmDoesNotReopenActiveFile() {
        XCTAssertFalse(SidebarOpenDecision.shouldOpen(
            isFile: true, selectedURL: a, activeURL: a, source: .keyboardConfirm))
    }

    func testKeyboardConfirmOnFolderNeverOpens() {
        let folder = URL(fileURLWithPath: "/ws/sub")
        XCTAssertFalse(SidebarOpenDecision.shouldOpen(
            isFile: false, selectedURL: folder, activeURL: nil, source: .keyboardConfirm))
    }
}
