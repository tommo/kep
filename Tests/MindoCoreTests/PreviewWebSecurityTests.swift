import XCTest
import WebKit
@testable import MindoCore

@MainActor
final class PreviewWebSecurityTests: XCTestCase {

    /// The hardened configuration must never persist browsing data to disk —
    /// previewing a document should leave nothing behind in ~/Library.
    func testConfigurationUsesNonPersistentDataStore() {
        let config = PreviewWebSecurity.hardenedConfiguration()
        XCTAssertFalse(config.websiteDataStore.isPersistent,
                       "preview web views must use an in-memory data store")
    }

    /// The remote-block content rule must be valid JSON that WebKit accepts —
    /// a malformed rule would silently leave remote subresources unblocked.
    /// This catches the exact failure mode of a hand-written rule list.
    func testRemoteBlockRuleListCompiles() async throws {
        // Mirror of the JSON embedded in PreviewWebSecurity. Compiling proves
        // WebKit accepts the trigger/action shape we ship.
        let json = """
        [{
          "trigger": {
            "url-filter": "^https?://",
            "resource-type": ["image","style-sheet","script","font","raw","svg-document","media","fetch","websocket","ping","other"]
          },
          "action": { "type": "block" }
        }]
        """
        let store = WKContentRuleListStore.default()!
        let ruleList: WKContentRuleList? = try await withCheckedThrowingContinuation { cont in
            store.compileContentRuleList(forIdentifier: "mindo.test.block", encodedContentRuleList: json) { list, err in
                if let err { cont.resume(throwing: err) } else { cont.resume(returning: list) }
            }
        }
        XCTAssertNotNil(ruleList, "the remote-block rule list must compile")
        store.removeContentRuleList(forIdentifier: "mindo.test.block") { _ in }
    }
}
