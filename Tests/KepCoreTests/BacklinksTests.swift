import XCTest
@testable import KepCore

final class BacklinksTests: XCTestCase {

    private let files = [
        URL(fileURLWithPath: "/ws/Notes.md"),
        URL(fileURLWithPath: "/ws/Roadmap.md"),
        URL(fileURLWithPath: "/ws/Ideas.md"),
        URL(fileURLWithPath: "/ws/data.csv"),
    ]

    private func corpus() -> [(url: URL, text: String)] {
        [
            (files[0], "Notes mention [[Roadmap]] and [[Ideas|some ideas]]."),
            (files[1], "Roadmap links back to [[Notes]] and to [[#Q3]]."),     // in-doc heading ignored
            (files[2], "Ideas reference [[roadmap#Q3]] (case-insensitive)."),  // resolves to Roadmap.md
            (files[3], "csv has no links"),
        ]
    }

    func testBacklinksToRoadmap() {
        let links = Backlinks.to(files[1], corpus: corpus(), allFiles: files)
        // Notes.md ([[Roadmap]]) + Ideas.md ([[roadmap#Q3]]) reference Roadmap.
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(Set(links.map { $0.source.lastPathComponent }), ["Notes.md", "Ideas.md"])
        XCTAssertTrue(links.contains { $0.link.heading == "Q3" })
    }

    func testSelfReferenceExcluded() {
        // Notes.md links to Roadmap/Ideas, not itself → no self backlink.
        let toNotes = Backlinks.to(files[0], corpus: corpus(), allFiles: files)
        XCTAssertEqual(toNotes.map { $0.source.lastPathComponent }, ["Roadmap.md"])
    }

    func testInDocHeadingLinkIsNotABacklink() {
        // [[#Q3]] in Roadmap.md must not count as a cross-document reference.
        let toRoadmap = Backlinks.to(files[1], corpus: corpus(), allFiles: files)
        XCTAssertFalse(toRoadmap.contains { $0.source.lastPathComponent == "Roadmap.md" })
    }

    func testSourcesDistinctAndSorted() {
        let extra = corpus() + [(files[2], "Ideas again: [[Notes]]")]
        let sources = Backlinks.sources(to: files[0], corpus: extra, allFiles: files)
        XCTAssertEqual(sources.map { $0.lastPathComponent }, ["Ideas.md", "Roadmap.md"])
    }

    func testNoBacklinks() {
        XCTAssertTrue(Backlinks.to(files[3], corpus: corpus(), allFiles: files).isEmpty)
    }

    // MARK: - Linked mentions (panel data)

    func testMentionsGroupBySourceWithContextLine() {
        let m = Backlinks.mentions(to: files[1], corpus: corpus(), allFiles: files)
        // Ideas.md + Notes.md reference Roadmap, path-sorted.
        XCTAssertEqual(m.map { $0.source.lastPathComponent }, ["Ideas.md", "Notes.md"])
        // Each mention carries the trimmed source line containing the link.
        XCTAssertEqual(m[0].snippets, ["Ideas reference [[roadmap#Q3]] (case-insensitive)."])
        XCTAssertEqual(m[1].snippets, ["Notes mention [[Roadmap]] and [[Ideas|some ideas]]."])
    }

    func testMentionsMultipleLinksFromOneSource() {
        // Two references to Notes from the same doc → one source, two snippets.
        let multi = [(files[1], "First [[Notes]] here.\nLater [[Notes#intro]] again.")]
        let m = Backlinks.mentions(to: files[0], corpus: multi, allFiles: files)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].snippets, ["First [[Notes]] here.", "Later [[Notes#intro]] again."])
    }

    func testMentionsEmptyWhenNoReferences() {
        XCTAssertTrue(Backlinks.mentions(to: files[3], corpus: corpus(), allFiles: files).isEmpty)
    }

    func testContextLineClampsOutOfBounds() {
        XCTAssertEqual(Backlinks.contextLine(in: "", around: NSRange(location: 5, length: 2)), "")
        XCTAssertEqual(Backlinks.contextLine(in: "  hi  ", around: NSRange(location: 99, length: 0)), "hi")
    }
}
