import XCTest
@testable import KepModel

final class ZipArchiveTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZipTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    @discardableResult
    private func zip(_ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    /// Build a .zip with `/usr/bin/zip` holding a tiny file (STORED) and a large
    /// repetitive one (DEFLATE, in a subfolder), then round-trip both.
    func testRoundTripStoredAndDeflate() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "no /usr/bin/zip")

        let small = "hi"
        let large = String(repeating: "The quick brown fox. ", count: 500)   // ~10.5 KB, compresses well
        try small.write(to: dir.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try large.write(to: dir.appendingPathComponent("nested/large.txt"), atomically: true, encoding: .utf8)

        try XCTSkipUnless(try zip(["-r", "-q", "out.zip", "small.txt", "nested"]) == 0, "zip failed")

        let data = try Data(contentsOf: dir.appendingPathComponent("out.zip"))
        let archive = try XCTUnwrap(ZipArchive(data: data), "archive must parse")

        let names = Set(archive.entries.filter { !$0.isDirectory }.map(\.path))
        XCTAssertTrue(names.contains("small.txt"))
        XCTAssertTrue(names.contains("nested/large.txt"))

        XCTAssertEqual(archive.data(for: "small.txt").flatMap { String(data: $0, encoding: .utf8) }, small)
        XCTAssertEqual(archive.data(for: "nested/large.txt").flatMap { String(data: $0, encoding: .utf8) }, large)
    }

    func testFirstDataWhereMatchesByPredicate() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "no /usr/bin/zip")
        try #"{"k":1}"#.write(to: dir.appendingPathComponent("content.json"), atomically: true, encoding: .utf8)
        try XCTSkipUnless(try zip(["-q", "doc.zip", "content.json"]) == 0, "zip failed")

        let archive = try XCTUnwrap(ZipArchive(data: try Data(contentsOf: dir.appendingPathComponent("doc.zip"))))
        let json = archive.firstData { $0.hasSuffix("content.json") }
        XCTAssertEqual(json.flatMap { String(data: $0, encoding: .utf8) }, #"{"k":1}"#)
        XCTAssertNil(archive.data(for: "missing.txt"))
    }

    func testNonZipDataReturnsNil() {
        XCTAssertNil(ZipArchive(data: Data("not a zip".utf8)))
        XCTAssertNil(ZipArchive(data: Data()))
    }

    func testInflateEmptyExpectation() {
        XCTAssertEqual(ZipArchive.inflate([1, 2, 3], expected: 0), Data())
    }
}
