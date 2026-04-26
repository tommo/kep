import SwiftUI
import MindoBase
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
    @AppStorage(PrefKeys.showHiddenFiles) private var showHiddenFiles: Bool = false
    @AppStorage(PrefKeys.hideFileExtensions) private var hideFileExtensions: Bool = false
    @AppStorage(PrefKeys.confirmBeforeQuit) private var confirmBeforeQuit: Bool = false
    @Environment(AppSession.self) private var session

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
            Section(L("prefs.general.section.workspace")) {
                Toggle(L("prefs.general.show_hidden_files"), isOn: $showHiddenFiles)
                    .onChange(of: showHiddenFiles) { _, _ in session.reloadAllWorkspaces() }
                Toggle(L("prefs.general.hide_file_extensions"), isOn: $hideFileExtensions)
            }
            Section(L("prefs.general.section.behavior")) {
                Toggle(L("prefs.general.confirm_before_quit"), isOn: $confirmBeforeQuit)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct EditorPrefs: View {
    @AppStorage(PrefKeys.editorFontSize) private var fontSize: Double = 13
    @AppStorage(PrefKeys.editorFontFamily) private var fontFamily: String = ""
    @AppStorage(PrefKeys.markdownPreviewSyncScroll) private var syncScroll: Bool = true
    @AppStorage(PrefKeys.autosaveOnBlur) private var autosaveOnBlur: Bool = true
    @AppStorage(PrefKeys.markdownSplitVertical) private var markdownSplitVertical: Bool = true
    @AppStorage(PrefKeys.plantumlSplitVertical) private var plantumlSplitVertical: Bool = true

    var body: some View {
        Form {
            Section(L("prefs.editor.section.text")) {
                Picker(L("prefs.editor.font_family"), selection: $fontFamily) {
                    Text(L("prefs.editor.font_family.system")).tag("")
                    ForEach(EditorFont.pickerFamilies, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Stepper(value: $fontSize, in: 9...24, step: 1) {
                    Text(String(format: L("prefs.editor.font_size_value"), Int(fontSize)))
                }
                Toggle(L("prefs.editor.sync_scroll"), isOn: $syncScroll)
                Toggle(L("prefs.editor.autosave_on_blur"), isOn: $autosaveOnBlur)
            }
            Section(L("prefs.editor.section.split")) {
                Picker(L("prefs.editor.split.markdown"), selection: $markdownSplitVertical) {
                    Text(L("prefs.editor.split.side_by_side")).tag(true)
                    Text(L("prefs.editor.split.top_bottom")).tag(false)
                }
                Picker(L("prefs.editor.split.plantuml"), selection: $plantumlSplitVertical) {
                    Text(L("prefs.editor.split.side_by_side")).tag(true)
                    Text(L("prefs.editor.split.top_bottom")).tag(false)
                }
                Text(L("prefs.editor.split.note")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct MindMapPrefs: View {
    @AppStorage(PrefKeys.mindmapVerticalGap) private var verticalGap: Double = 14
    @AppStorage(PrefKeys.mindmapHorizontalGap) private var horizontalGap: Double = 60
    @AppStorage(PrefKeys.mindmapConnectorStyle) private var connectorStyle: String = "bezier"
    @AppStorage(PrefKeys.mindmapConnectorWidth) private var connectorWidth: Double = 1.5
    @AppStorage(PrefKeys.mindmapInheritFillColor) private var inheritFillColor: Bool = false
    @AppStorage(PrefKeys.mindmapTrimTopicText) private var trimTopicText: Bool = false
    @AppStorage(PrefKeys.mindmapShowGrid) private var showGrid: Bool = false
    @AppStorage(PrefKeys.mindmapGridStep) private var gridStep: Double = 16
    @AppStorage(PrefKeys.mindmapDropShadow) private var dropShadow: Bool = true
    @AppStorage(PrefKeys.mindmapUnfoldCollapsedDropTarget) private var unfoldOnDrop: Bool = true
    @AppStorage(PrefKeys.mindmapSmartTextPaste) private var smartTextPaste: Bool = true
    @AppStorage(PrefKeys.mindmapCornerRadius) private var cornerRadius: Double = 0

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
            Section(L("prefs.mindmap.section.connectors")) {
                Picker(L("prefs.mindmap.connector_style"), selection: $connectorStyle) {
                    Text(L("prefs.mindmap.connector_style.bezier")).tag("bezier")
                    Text(L("prefs.mindmap.connector_style.polyline")).tag("polyline")
                }
                Stepper(value: $connectorWidth, in: 0.5...4.0, step: 0.5) {
                    Text(String(format: L("prefs.mindmap.connector_width"), connectorWidth))
                }
            }
            Section(L("prefs.mindmap.section.shape")) {
                Stepper(value: $cornerRadius, in: 0...32, step: 1) {
                    if cornerRadius > 0 {
                        Text(String(format: L("prefs.mindmap.corner_radius_value"), Int(cornerRadius)))
                    } else {
                        Text(L("prefs.mindmap.corner_radius_theme"))
                    }
                }
            }
            Section(L("prefs.mindmap.section.behavior")) {
                Toggle(L("prefs.mindmap.inherit_fill_color"), isOn: $inheritFillColor)
                Toggle(L("prefs.mindmap.trim_topic_text"), isOn: $trimTopicText)
                Toggle(L("prefs.mindmap.drop_shadow"), isOn: $dropShadow)
                Toggle(L("prefs.mindmap.unfold_on_drop"), isOn: $unfoldOnDrop)
                Toggle(L("prefs.mindmap.smart_text_paste"), isOn: $smartTextPaste)
            }
            Section(L("prefs.mindmap.section.grid")) {
                Toggle(L("prefs.mindmap.show_grid"), isOn: $showGrid)
                Stepper(value: $gridStep, in: 4...64, step: 2) {
                    Text(String(format: L("prefs.mindmap.grid_step"), Int(gridStep)))
                }
                .disabled(!showGrid)
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

