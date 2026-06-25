import WebKit

/// Hardening for the document-preview `WKWebView`s (markdown / PlantUML / note
/// hover / PDF export). Kep is a local-first app: previewing a note must
/// never silently reach out to the network. Two guarantees:
///
///   1. **Non-persistent data store** — cookies, caches, and localStorage live
///      in memory only, so nothing a previewed document touches is written to
///      `~/Library`. Always applied, regardless of the pref.
///
///   2. **Remote-subresource block** — a compiled `WKContentRuleList` blocks
///      every `http(s)` *subresource* load (remote images, CSS, scripts,
///      fonts, tracking pixels). The main-frame navigation still reaches the
///      nav delegate, which routes clicked external links to the system
///      browser. Local `file:`/`data:` resources are untouched, so legitimate
///      relative images and inline-SVG diagrams keep rendering. Gated by
///      `PrefKeys.privacyBlockRemoteContent` (default ON).
///
/// The rule list compiles asynchronously; `warmUp()` (called at launch) primes
/// the cache so the first preview is already protected. If a config is built
/// before compilation finishes, the rule is added to that web view's content
/// controller the moment it becomes ready — it applies to all subsequent loads.
public enum PreviewWebSecurity {
    /// Identifier under which the compiled rule list is cached by WebKit.
    private static let ruleListIdentifier = "kep.block-remote-subresources"

    /// Blocks http(s) loads for every resource type *except* the top-level
    /// document (so the main-frame navigation still reaches the nav delegate)
    /// and popups. `url-filter` is a regex over the absolute URL.
    private static let ruleListJSON = """
    [{
      "trigger": {
        "url-filter": "^https?://",
        "resource-type": ["image","style-sheet","script","font","raw","svg-document","media","fetch","websocket","ping","other"]
      },
      "action": { "type": "block" }
    }]
    """

    private static var cachedRuleList: WKContentRuleList?

    /// Compile the rule list ahead of first use so launch-time previews are
    /// already covered. Safe to call repeatedly; no-op once cached.
    @MainActor public static func warmUp() {
        ensureRuleList { _ in }
    }

    /// A `WKWebViewConfiguration` with the in-memory data store applied and the
    /// remote-block rule attached (when the pref is on). Callers may further
    /// mutate the returned config (e.g. add script-message handlers) before
    /// constructing the web view.
    @MainActor public static func hardenedConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        // In-memory only: no cookies/cache/localStorage persisted to disk.
        config.websiteDataStore = .nonPersistent()

        guard PrefKeys.bool(PrefKeys.privacyBlockRemoteContent, fallback: true) else {
            return config
        }
        let controller = config.userContentController
        ensureRuleList { ruleList in
            guard let ruleList else { return }
            controller.add(ruleList)
        }
        return config
    }

    /// Resolve the compiled rule list, compiling + caching on first call.
    /// The completion runs synchronously when already cached, else after the
    /// async compile finishes.
    @MainActor private static func ensureRuleList(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let cached = cachedRuleList { completion(cached); return }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: ruleListIdentifier,
            encodedContentRuleList: ruleListJSON
        ) { ruleList, _ in
            if let ruleList { cachedRuleList = ruleList }
            completion(ruleList)
        }
    }
}
