import XCTest
import MindoCore

final class PrefKeysTests: XCTestCase {

    private let testKey = "mindo.prefs.test.\(UUID().uuidString)"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testDoubleReturnsFallbackWhenUnset() {
        XCTAssertEqual(PrefKeys.double(testKey, fallback: 42), 42, accuracy: 1e-9)
    }

    func testDoubleReturnsStoredValueWhenPositive() {
        UserDefaults.standard.set(7.5, forKey: testKey)
        XCTAssertEqual(PrefKeys.double(testKey, fallback: 99), 7.5, accuracy: 1e-9)
    }

    func testDoubleReturnsFallbackWhenStoredZero() {
        // Zero is the same as "missing" for our use cases (font size,
        // gap) — treat both as "use the default".
        UserDefaults.standard.set(0, forKey: testKey)
        XCTAssertEqual(PrefKeys.double(testKey, fallback: 13), 13, accuracy: 1e-9)
    }

    func testBoolReturnsFallbackWhenUnset() {
        XCTAssertTrue(PrefKeys.bool(testKey, fallback: true))
        XCTAssertFalse(PrefKeys.bool(testKey, fallback: false))
    }

    func testBoolReturnsStoredFalseEvenWhenFallbackTrue() {
        UserDefaults.standard.set(false, forKey: testKey)
        XCTAssertFalse(PrefKeys.bool(testKey, fallback: true),
                       "stored false must beat fallback true (regression: standard.bool returns false for missing keys too)")
    }
}
