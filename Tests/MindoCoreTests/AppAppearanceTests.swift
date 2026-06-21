import XCTest
import AppKit
@testable import MindoBase
@testable import MindoCore

final class AppAppearanceTests: XCTestCase {

    func testNSAppearanceMapping() {
        XCTAssertNil(AppAppearance.system.nsAppearance, "system follows the OS (nil)")
        XCTAssertEqual(AppAppearance.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppAppearance.dark.nsAppearance?.name, .darkAqua)
    }

    func testCurrentDefaultsToSystem() {
        let key = PrefKeys.appAppearance
        let prior = UserDefaults.standard.string(forKey: key)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(AppAppearance.current, .system)
        UserDefaults.standard.set("dark", forKey: key)
        XCTAssertEqual(AppAppearance.current, .dark)
        UserDefaults.standard.set("garbage", forKey: key)
        XCTAssertEqual(AppAppearance.current, .system, "invalid value → system")
    }
}
