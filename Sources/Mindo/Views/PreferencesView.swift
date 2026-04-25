import SwiftUI
import MindoCore

/// Tabbed preferences sheet wired into SwiftUI's Settings scene (⌘,).
/// Persists via @AppStorage so editors that observe the same keys
/// re-render automatically when the user toggles something.
struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefs()
                .tabItem { Label(L("prefs.tab.general"), systemImage: "gear") }
            EditorPrefs()
                .tabItem { Label(L("prefs.tab.editor"), systemImage: "text.alignleft") }
            MindMapPrefs()
                .tabItem { Label(L("prefs.tab.mindmap"), systemImage: "brain") }
            AIPrefs()
                .tabItem { Label(L("prefs.tab.ai"), systemImage: "sparkles") }
        }
        .frame(width: 480, height: 320)
    }
}

private struct GeneralPrefs: View {
    @AppStorage(PrefKeys.theme) private var theme: String = ThemeChoice.light.rawValue
    @AppStorage(PrefKeys.outlineOpenByDefault) private var outlineOpen: Bool = true

    var body: some View {
        Form {
            Section(L("prefs.general.section.appearance")) {
                Picker(L("prefs.general.theme"), selection: $theme) {
                    Text(L("menu.view.theme.light")).tag(ThemeChoice.light.rawValue)
                    Text(L("menu.view.theme.dark")).tag(ThemeChoice.dark.rawValue)
                    Text(L("menu.view.theme.classic")).tag(ThemeChoice.classic.rawValue)
                }
                Toggle(L("prefs.general.outline_default_open"), isOn: $outlineOpen)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct EditorPrefs: View {
    @AppStorage(PrefKeys.editorFontSize) private var fontSize: Double = 13
    @AppStorage(PrefKeys.markdownPreviewSyncScroll) private var syncScroll: Bool = true
    @AppStorage(PrefKeys.autosaveOnBlur) private var autosaveOnBlur: Bool = true

    var body: some View {
        Form {
            Section(L("prefs.editor.section.text")) {
                Stepper(value: $fontSize, in: 9...24, step: 1) {
                    Text(String(format: L("prefs.editor.font_size_value"), Int(fontSize)))
                }
                Toggle(L("prefs.editor.sync_scroll"), isOn: $syncScroll)
                Toggle(L("prefs.editor.autosave_on_blur"), isOn: $autosaveOnBlur)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct MindMapPrefs: View {
    @AppStorage(PrefKeys.mindmapVerticalGap) private var verticalGap: Double = 14
    @AppStorage(PrefKeys.mindmapHorizontalGap) private var horizontalGap: Double = 60

    var body: some View {
        Form {
            Section(L("prefs.mindmap.section.layout")) {
                Stepper(value: $verticalGap, in: 4...60, step: 2) {
                    Text(String(format: L("prefs.mindmap.vertical_gap"), Int(verticalGap)))
                }
                Stepper(value: $horizontalGap, in: 20...160, step: 4) {
                    Text(String(format: L("prefs.mindmap.horizontal_gap"), Int(horizontalGap)))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AIPrefs: View {
    @AppStorage(PrefKeys.aiStreamingEnabled) private var streaming: Bool = true

    var body: some View {
        Form {
            Section(L("prefs.ai.section.behavior")) {
                Toggle(L("prefs.ai.streaming"), isOn: $streaming)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

