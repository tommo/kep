import XCTest

/// Smoke tests for the app's localization files. Verifies both the English
/// and Simplified Chinese strings files exist on disk inside the Kep
/// executable's resource layout, and that they share the same set of keys.
///
/// The Kep SPM executable target ships its `.strings` files via
/// `resources: [.process("Resources")]`. The processed bundle lands next to
/// the test executable as `Kep_KepApp.bundle` (SPM convention) — we walk
/// up to find it; test is skipped (not failed) if the layout shifts.
final class I18nTests: XCTestCase {

    private struct ResourcePaths {
        let en: URL
        let zh: URL
    }

    private func locateStringsFiles() -> ResourcePaths? {
        let fm = FileManager.default
        // First try: the test's resource bundle layout (works when SPM has
        // packaged the strings alongside the test binary). Walk a few levels
        // up looking for `*Kep.bundle/Contents/Resources/{lproj}`.
        var dir: URL? = Bundle(for: type(of: self)).bundleURL
        for _ in 0..<6 {
            guard let url = dir else { break }
            if let candidate = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .first(where: { $0.lastPathComponent.hasSuffix("_Kep.bundle") || $0.lastPathComponent == "Kep.bundle" }) {
                let resources = candidate.appendingPathComponent("Contents/Resources")
                let en = resources.appendingPathComponent("en.lproj/Localizable.strings")
                let zh = resources.appendingPathComponent("zh-Hans.lproj/Localizable.strings")
                if fm.fileExists(atPath: en.path), fm.fileExists(atPath: zh.path) {
                    return ResourcePaths(en: en, zh: zh)
                }
            }
            dir = url.deletingLastPathComponent()
        }
        // Fallback: walk up from this test source file to the package root
        // and read the .strings directly out of the source tree. Fixed
        // relative path inside SPM project layout.
        let sourceFile = URL(fileURLWithPath: #filePath)
        var packageRoot = sourceFile
            .deletingLastPathComponent()  // KepCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        // If we're in a worktree symlink, normalize.
        packageRoot = packageRoot.standardizedFileURL
        let en = packageRoot.appendingPathComponent("Sources/Kep/Resources/en.lproj/Localizable.strings")
        let zh = packageRoot.appendingPathComponent("Sources/Kep/Resources/zh-Hans.lproj/Localizable.strings")
        if fm.fileExists(atPath: en.path), fm.fileExists(atPath: zh.path) {
            return ResourcePaths(en: en, zh: zh)
        }
        return nil
    }

    /// Pull every `"key" = "value";` line out of a .strings file (very loose parser
    /// — enough for the smoke test).
    private func parseKeys(_ url: URL) throws -> Set<String> {
        let text = try String(contentsOf: url, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #""([^"]+)"\s*=\s*"[^"]*";"#)
        var keys: Set<String> = []
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { match, _, _ in
            guard let m = match else { return }
            let key = (text as NSString).substring(with: m.range(at: 1))
            keys.insert(key)
        }
        return keys
    }

    func testStringsFilesExistAndContainExpectedKeys() throws {
        guard let paths = locateStringsFiles() else {
            throw XCTSkip("Kep localized resources not present alongside tests")
        }
        let enText = try String(contentsOf: paths.en, encoding: .utf8)
        let zhText = try String(contentsOf: paths.zh, encoding: .utf8)
        XCTAssertTrue(enText.contains("\"menu.file.save\""))
        XCTAssertTrue(enText.contains("\"Save\""))
        XCTAssertTrue(zhText.contains("\"menu.file.save\""))
        XCTAssertTrue(zhText.contains("\"保存\""))
    }

    func testEnglishAndChineseSetsHaveTheSameKeys() throws {
        guard let paths = locateStringsFiles() else {
            throw XCTSkip("Kep localized resources not present alongside tests")
        }
        let en = try parseKeys(paths.en)
        let zh = try parseKeys(paths.zh)
        XCTAssertEqual(en, zh,
                       "en and zh-Hans Localizable.strings should declare the same keys; " +
                       "diff = \(en.symmetricDifference(zh))")
    }
}
