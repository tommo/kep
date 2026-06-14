import Foundation

/// What to do when something navigates inside the markdown preview WKWebView.
public enum MarkdownLinkAction: Equatable {
    /// Let the web view perform the navigation (initial HTML render, JS
    /// driven loads, in-page `#anchor` scrolls).
    case allow
    /// A web/mail/tel link the user clicked — open in the system handler,
    /// cancel the in-view navigation.
    case openExternally(URL)
    /// A file / relative link the user clicked — hand off to the host so it
    /// can open the document; cancel the in-view navigation.
    case openFile(URL)
}

/// Decides how the preview should react to a navigation. Split out as a
/// pure function so the policy — "external links leave the app, file links
/// open in the app, everything else renders in place" — is unit-testable
/// without spinning up WebKit.
///
/// The bug this guards: with no navigation delegate, clicking ANY link in
/// the preview replaced the rendered markdown with the link target (the
/// preview "swallowed" the click). Only `.linkActivated` navigations are
/// user clicks; the initial `loadHTMLString` and JS scroll bridge arrive as
/// other types and must always be allowed.
/// Resolves the `baseURL` the preview should render against, given the
/// document's on-disk URL. Returns the document's *directory* so relative
/// references resolve as a browser would. Nil for an unsaved document (no
/// folder to resolve against). Pure for unit-testing.
public enum MarkdownPreviewBase {
    public static func baseURL(forDocumentAt url: URL?) -> URL? {
        guard let url else { return nil }
        // A file URL points at the document; relative refs are siblings, so
        // strip the last component to get the containing directory.
        return url.deletingLastPathComponent()
    }
}

public enum MarkdownLinkPolicy {
    private static let externalSchemes: Set<String> = ["http", "https", "mailto", "tel", "ftp"]

    public static func decide(url: URL?, isLinkActivation: Bool) -> MarkdownLinkAction {
        // Non-click navigations (render, reload, JS) always proceed.
        guard isLinkActivation, let url else { return .allow }

        let scheme = url.scheme?.lowercased()

        // In-page anchor (e.g. a table-of-contents "#section") — let the web
        // view scroll itself. Detect both real fragments and the bare "#..."
        // form that has no scheme/host.
        let isPureFragment = (url.fragment != nil)
            && url.path.isEmpty
            && (url.host == nil)
        if isPureFragment { return .allow }

        if let scheme, externalSchemes.contains(scheme) {
            return .openExternally(url)
        }
        if scheme == "file" {
            return .openFile(url)
        }
        // No scheme → a relative link to another doc; treat as a file open.
        if scheme == nil {
            return .openFile(url)
        }
        // Unknown scheme (e.g. custom app links) — open externally rather
        // than clobbering the preview.
        return .openExternally(url)
    }
}
