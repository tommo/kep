import XCTest
import KepBase

final class SnippetExpanderTests: XCTestCase {

    private let referenceDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 26
        c.hour = 14; c.minute = 30
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    func testReturnsTemplateUnchangedWhenNoPlaceholders() {
        XCTAssertEqual(SnippetExpander.expand("hello world"), "hello world")
        XCTAssertEqual(SnippetExpander.expand(""), "")
    }

    func testExpandsDateAndTime() {
        // Lock the formatter to UTC for the assertion so the test is timezone-agnostic.
        let prevTZ = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "UTC")!
        defer { NSTimeZone.default = prevTZ }

        let ctx = SnippetExpander.Context(date: referenceDate)
        XCTAssertEqual(SnippetExpander.expand("Today: ${date}", context: ctx), "Today: 2026-04-26")
        XCTAssertEqual(SnippetExpander.expand("At ${time}", context: ctx), "At 14:30")
        XCTAssertEqual(SnippetExpander.expand("Stamp ${datetime}", context: ctx), "Stamp 2026-04-26 14:30")
    }

    func testExpandsFilenameAndTitle() {
        let ctx = SnippetExpander.Context(filename: "report", title: "Q2 Plan")
        XCTAssertEqual(SnippetExpander.expand("[${filename}] ${title}", context: ctx),
                       "[report] Q2 Plan")
    }

    func testExpandsUserToFullName() {
        let result = SnippetExpander.expand("by ${user}")
        XCTAssertTrue(result.hasPrefix("by "))
        XCTAssertFalse(result.contains("${user}"), "user placeholder should be replaced")
    }

    func testUnknownPlaceholdersPassThrough() {
        // An unknown placeholder is preserved verbatim while a known one in the
        // same string still expands. (TZ-agnostic: assert structure, not the
        // date value, which testExpandsDateAndTime already pins.)
        let out = SnippetExpander.expand("set ${nope}=${date}", context: .init(date: referenceDate))
        XCTAssertTrue(out.hasPrefix("set ${nope}="), "unknown placeholder must pass through")
        XCTAssertFalse(out.contains("${date}"), "known placeholder must still expand")
        XCTAssertTrue(SnippetExpander.expand("hello ${unknown}", context: .init()).contains("${unknown}"))
    }

    func testEmptyContextValuesExpandToEmptyString() {
        let ctx = SnippetExpander.Context(filename: "", title: "")
        XCTAssertEqual(SnippetExpander.expand("[${filename}]${title}", context: ctx), "[]")
    }
}
