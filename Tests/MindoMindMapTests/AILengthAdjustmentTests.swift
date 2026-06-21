import XCTest
@testable import MindoGenAI

final class AILengthAdjustmentTests: XCTestCase {
    func testAppliedAppendsDirectiveOnNewParagraph() {
        let p = AILengthAdjustment.shorter.applied(to: "Summarize the meeting notes.")
        XCTAssertTrue(p.hasPrefix("Summarize the meeting notes.\n\n"))
        XCTAssertTrue(p.contains(AILengthAdjustment.shorter.directive))
    }

    func testAppliedTrimsTrailingWhitespace() {
        let p = AILengthAdjustment.longer.applied(to: "Explain.\n\n   ")
        XCTAssertEqual(p, "Explain.\n\n\(AILengthAdjustment.longer.directive)")
    }

    func testAppliedToEmptyBaseIsJustDirective() {
        XCTAssertEqual(AILengthAdjustment.shorter.applied(to: "   "),
                       AILengthAdjustment.shorter.directive)
    }

    func testShorterAndLongerHaveDistinctDirectives() {
        XCTAssertNotEqual(AILengthAdjustment.shorter.directive, AILengthAdjustment.longer.directive)
        XCTAssertEqual(AILengthAdjustment.allCases, [.shorter, .longer])
    }
}
