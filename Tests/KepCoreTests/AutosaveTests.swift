import XCTest
@testable import KepCore

final class AutosaveTests: XCTestCase {

    func testAutosavesWhenDirtyAndHasURLAndSavable() {
        XCTAssertTrue(Autosave.shouldAutosave(isDirty: true, hasFileURL: true, isSavable: true))
    }

    func testSkipsCleanDocs() {
        XCTAssertFalse(Autosave.shouldAutosave(isDirty: false, hasFileURL: true, isSavable: true))
    }

    func testSkipsUntitledDocs() {
        // No URL → silent autosave can't pick a path on the user's behalf.
        XCTAssertFalse(Autosave.shouldAutosave(isDirty: true, hasFileURL: false, isSavable: true))
    }

    func testSkipsUnsavableKinds() {
        // .unsupported docs (binary previews) can't round-trip through save.
        XCTAssertFalse(Autosave.shouldAutosave(isDirty: true, hasFileURL: true, isSavable: false))
    }
}
