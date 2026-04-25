import XCTest
@testable import MindoCore

final class FileWatcherTests: XCTestCase {

    /// Touching the watched file should trigger a `.write` or `.extend` event.
    /// We give it a generous 3-second window since file system events can be
    /// coalesced.
    func testFiresOnExternalWrite() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mindo-fw-\(UUID()).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let exp = expectation(description: "file watcher fires")
        let watcher = FileWatcher(url: tmp, queue: .global()) { event in
            if event.contains(.write) || event.contains(.extend) {
                exp.fulfill()
            }
        }
        XCTAssertTrue(watcher.start(), "watcher should start")
        // Issue an external append.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            if let handle = try? FileHandle(forWritingTo: tmp) {
                handle.seekToEndOfFile()
                handle.write("world".data(using: .utf8)!)
                try? handle.close()
            }
        }
        wait(for: [exp], timeout: 3.0)
        watcher.stop()
        XCTAssertFalse(watcher.isWatching)
    }

    func testStartFailsForMissingFile() {
        let bogus = URL(fileURLWithPath: "/var/empty/does-not-exist-\(UUID())")
        let watcher = FileWatcher(url: bogus) { _ in }
        XCTAssertFalse(watcher.start())
    }
}
