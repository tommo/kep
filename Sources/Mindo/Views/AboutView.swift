import SwiftUI
import AppKit

/// Help → About Mindo sheet. Reads name + version + build from the
/// running bundle so the values stay correct across releases without
/// editing the view.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "kep"
    }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "brain")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.tint)
            }
            Text(appName).font(.title2).bold()
            Text(String(format: L("about.version_format"), version, build))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L("about.tagline"))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Button(L("about.button.releases")) {
                    if let url = URL(string: ReleaseChecker.releasesPageURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button(L("about.button.close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360, height: 320)
    }
}

/// Hits GitHub Releases (or any other configurable URL) to learn whether a
/// newer version is published. Pure URL logic — UI lives in MindoApp's
/// "Check for Updates…" menu item.
public enum ReleaseChecker {
    /// Override at boot via UserDefaults (`mindo.update.releasesURL`) for
    /// forks or staging environments.
    public static var releasesPageURL: String {
        UserDefaults.standard.string(forKey: "mindo.update.releasesURL")
            ?? "https://github.com/mindo-app/mindo/releases"
    }
}
