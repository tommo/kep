import XCTest
@testable import MindoCore

final class KBContextTests: XCTestCase {

    private let files = [
        URL(fileURLWithPath: "/ws/Architecture.md"),
        URL(fileURLWithPath: "/ws/Auth.md"),
        URL(fileURLWithPath: "/ws/Billing.md"),
        URL(fileURLWithPath: "/ws/Roadmap.md"),
    ]

    private func corpus() -> [(url: URL, text: String)] {
        [
            (files[0], "Architecture references [[Auth]] and [[Billing]]."),
            (files[1], "Auth links to [[Architecture]]."),
            (files[2], "Billing links to [[Architecture]]."),
            (files[3], "Roadmap mentions nothing."),
        ]
    }

    func testOutgoingLinksResolvedDistinct() {
        let out = KBContext.outgoingLinks(in: "see [[Auth]], [[Billing]], [[Auth]], [[Nope]]", allFiles: files)
        XCTAssertEqual(out, ["Auth", "Billing"])   // distinct, resolved only
    }

    func testSummaryHasOutgoingAndIncoming() {
        let s = KBContext.summary(for: files[0], text: corpus()[0].text, corpus: corpus(), allFiles: files)
        XCTAssertEqual(s, "Links to: Auth, Billing. Linked from: Auth, Billing.")
    }

    func testSummaryOnlyIncoming() {
        // Auth links out to Architecture (1), and is linked from Architecture.
        let s = KBContext.summary(for: files[1], text: corpus()[1].text, corpus: corpus(), allFiles: files)
        XCTAssertEqual(s, "Links to: Architecture. Linked from: Architecture.")
    }

    func testNoLinksReturnsNil() {
        XCTAssertNil(KBContext.summary(for: files[3], text: "plain", corpus: corpus(), allFiles: files))
    }
}
