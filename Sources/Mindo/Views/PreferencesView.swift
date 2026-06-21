import AppKit
import SwiftUI
import MindoBase
import MindoCore
import MindoGenAI
import MindoMindMap
import MindoCSV

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
        .frame(width: 500, height: 460)
    }
}

private struct GeneralPrefs: View {
    @AppStorage(PrefKeys.theme) private var theme: String = ThemeChoice.light.rawValue
    @AppStorage(PrefKeys.appAppearance) private var appAppearance: String = AppAppearance.system.rawValue
    @AppStorage(PrefKeys.outlineOpenByDefault) private var outlineOpen: Bool = true
    @AppStorage(PrefKeys.showHiddenFiles) private var showHiddenFiles: Bool = false
    @AppStorage(PrefKeys.hideFileExtensions) private var hideFileExtensions: Bool = false
    @AppStorage(PrefKeys.confirmBeforeQuit) private var confirmBeforeQuit: Bool = false
    @AppStorage(PrefKeys.openLastFiles) private var openLastFiles: Bool = true
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            Section(L("prefs.general.section.appearance")) {
                Picker(L("prefs.general.app_appearance"), selection: $appAppearance) {
                    Text(L("prefs.appearance.system")).tag(AppAppearance.system.rawValue)
                    Text(L("prefs.appearance.light")).tag(AppAppearance.light.rawValue)
                    Text(L("prefs.appearance.dark")).tag(AppAppearance.dark.rawValue)
                }
                .onChange(of: appAppearance) { _, new in
                    (AppAppearance(rawValue: new) ?? .system).apply()
                }
                Picker(L("prefs.general.theme"), selection: $theme) {
                    Text(L("menu.view.theme.light")).tag(ThemeChoice.light.rawValue)
                    Text(L("menu.view.theme.dark")).tag(ThemeChoice.dark.rawValue)
                    Text(L("menu.view.theme.classic")).tag(ThemeChoice.classic.rawValue)
                    Text(L("menu.view.theme.custom")).tag(ThemeChoice.custom.rawValue)
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
                Toggle(L("prefs.general.open_last_files"), isOn: $openLastFiles)
            }
            RestoreDefaultsRow(group: .general)
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Shared "Restore Defaults" footer button for a Settings tab. Clears the
/// group's keys; the `@AppStorage` controls above snap back to their
/// declared defaults on the next render.
private struct RestoreDefaultsRow: View {
    let group: PrefResetGroup
    var body: some View {
        Section {
            HStack {
                Spacer()
                Button(L("prefs.restore_defaults"), role: .destructive) {
                    PrefReset.reset(group)
                }
            }
        }
    }
}

private struct EditorPrefs: View {
    @AppStorage(PrefKeys.editorFontSize) private var fontSize: Double = 13
    @AppStorage(PrefKeys.editorFontFamily) private var fontFamily: String = ""
    @AppStorage(PrefKeys.markdownPreviewSyncScroll) private var syncScroll: Bool = true
    @AppStorage(PrefKeys.autosaveOnBlur) private var autosaveOnBlur: Bool = true
    @AppStorage(PrefKeys.markdownSplitVertical) private var markdownSplitVertical: Bool = true
    @AppStorage(PrefKeys.plantumlSplitVertical) private var plantumlSplitVertical: Bool = true
    @AppStorage(PrefKeys.plantumlGraphvizPath) private var graphvizPath: String = ""
    @AppStorage(PrefKeys.markdownPreviewFont) private var previewFont: String = ""
    @AppStorage(PrefKeys.markdownPreviewMonoFont) private var previewMonoFont: String = ""
    @AppStorage(PrefKeys.csvFontFamily) private var csvFontFamily: String = ""
    @AppStorage(PrefKeys.csvFontSize) private var csvFontSize: Double = 12

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
            Section(L("prefs.editor.section.preview")) {
                Picker(L("prefs.editor.preview_font"), selection: $previewFont) {
                    Text(L("prefs.editor.font_family.system")).tag("")
                    ForEach(EditorFont.pickerFamilies, id: \.self) { name in Text(name).tag(name) }
                }
                Picker(L("prefs.editor.preview_mono_font"), selection: $previewMonoFont) {
                    Text(L("prefs.editor.font_family.system")).tag("")
                    ForEach(EditorFont.pickerFamilies, id: \.self) { name in Text(name).tag(name) }
                }
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
            Section(L("prefs.editor.section.plantuml")) {
                HStack {
                    TextField(L("prefs.editor.plantuml.dotpath_placeholder"), text: $graphvizPath)
                        .textFieldStyle(.roundedBorder)
                    Button(L("prefs.editor.plantuml.dotpath_pick")) { pickGraphvizPath() }
                }
                Text(L("prefs.editor.plantuml.dotpath_note")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("prefs.editor.section.csv")) {
                Picker(L("prefs.editor.csv_font"), selection: $csvFontFamily) {
                    Text(L("prefs.editor.font_family.system")).tag("")
                    ForEach(EditorFont.pickerFamilies, id: \.self) { name in Text(name).tag(name) }
                }
                .onChange(of: csvFontFamily) { _, _ in NotificationCenter.default.post(name: .csvFontChanged, object: nil) }
                Stepper(value: $csvFontSize, in: 9...16, step: 1) {
                    Text(String(format: L("prefs.editor.font_size_value"), Int(csvFontSize)))
                }
                .onChange(of: csvFontSize) { _, _ in NotificationCenter.default.post(name: .csvFontChanged, object: nil) }
            }
            EditorColorPrefs()
            RestoreDefaultsRow(group: .editor)
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Open a file picker to choose the dot binary. Reads back into the
    /// pref via @AppStorage so the renderer picks it up on the next
    /// preview refresh.
    private func pickGraphvizPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = L("prefs.editor.plantuml.dotpath_pick")
        if panel.runModal() == .OK, let url = panel.url {
            graphvizPath = url.path
        }
    }
}

/// Editor syntax-color customization — a toggle plus a color well per token
/// role. Edits the override for the *effective* appearance (light or dark);
/// changes persist + post `.editorThemeChanged` so open editors restyle live.
private struct EditorColorPrefs: View {
    @State private var theme = EditorThemeStore.current

    private struct Role: Identifiable {
        let id: String
        let label: String
        let override: WritableKeyPath<EditorThemeColors, String?>
        let base: KeyPath<SyntaxPalette, NSColor>
    }
    private static let roles: [Role] = [
        Role(id: "text", label: "Text", override: \.text, base: \.text),
        Role(id: "keyword", label: "Keyword / Heading", override: \.keyword, base: \.keyword),
        Role(id: "string", label: "String / Code", override: \.string, base: \.string),
        Role(id: "comment", label: "Comment / Quote", override: \.comment, base: \.comment),
        Role(id: "link", label: "Link", override: \.link, base: \.link),
        Role(id: "punctuation", label: "Punctuation", override: \.punctuation, base: \.punctuation),
    ]

    /// Which appearance's colors we're editing right now.
    private var dark: Bool {
        switch AppAppearance.current {
        case .light: return false
        case .dark: return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    var body: some View {
        Section(L("prefs.editor.section.colors")) {
            Toggle(L("prefs.editor.customize_colors"), isOn: Binding(
                get: { theme.enabled },
                set: { theme.enabled = $0; EditorThemeStore.save(theme) }
            ))
            if theme.enabled {
                Text(String(format: L("prefs.editor.colors_editing_fmt"),
                            dark ? L("prefs.appearance.dark") : L("prefs.appearance.light")))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Self.roles) { role in
                    ColorPicker(role.label, selection: binding(for: role), supportsOpacity: false)
                }
                Button(L("prefs.editor.colors_reset")) {
                    if dark { theme.dark = EditorThemeColors() } else { theme.light = EditorThemeColors() }
                    EditorThemeStore.save(theme)
                }
            }
        }
    }

    private func binding(for role: Role) -> Binding<Color> {
        Binding(
            get: {
                let hex = (dark ? theme.dark : theme.light)[keyPath: role.override]
                let base = (dark ? SyntaxPalette.dark : SyntaxPalette.light)[keyPath: role.base]
                return Color(nsColor: hex.flatMap(NSColor.init(hexString:)) ?? base)
            },
            set: { newColor in
                let hex = NSColor(newColor).hexString
                if dark { theme.dark[keyPath: role.override] = hex }
                else { theme.light[keyPath: role.override] = hex }
                EditorThemeStore.save(theme)
            }
        )
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
    @AppStorage(PrefKeys.mindmapBorderWidth) private var borderWidth: Double = 0
    @AppStorage(PrefKeys.mindmapHighlightPath) private var highlightPath: Bool = false

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
                Stepper(value: $borderWidth, in: 0...8, step: 0.5) {
                    if borderWidth > 0 {
                        Text(String(format: L("prefs.mindmap.border_width_value"), borderWidth))
                    } else {
                        Text(L("prefs.mindmap.border_width_default"))
                    }
                }
            }
            Section(L("prefs.mindmap.section.behavior")) {
                Toggle(L("prefs.mindmap.inherit_fill_color"), isOn: $inheritFillColor)
                Toggle(L("prefs.mindmap.trim_topic_text"), isOn: $trimTopicText)
                Toggle(L("prefs.mindmap.drop_shadow"), isOn: $dropShadow)
                Toggle(L("prefs.mindmap.unfold_on_drop"), isOn: $unfoldOnDrop)
                Toggle(L("prefs.mindmap.smart_text_paste"), isOn: $smartTextPaste)
                Toggle(L("prefs.mindmap.highlight_path"), isOn: $highlightPath)
            }
            Section(L("prefs.mindmap.section.grid")) {
                Toggle(L("prefs.mindmap.show_grid"), isOn: $showGrid)
                Stepper(value: $gridStep, in: 4...64, step: 2) {
                    Text(String(format: L("prefs.mindmap.grid_step"), Int(gridStep)))
                }
                .disabled(!showGrid)
            }
            CanvasColorPrefs()
            RestoreDefaultsRow(group: .mindmap)
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Custom mind-map canvas color editor — shown when the active theme is
/// "Custom". A color well per canvas role; edits persist + bump the canvas
/// revision so an open canvas restyles live. Reuses the EditorColorPrefs shape.
private struct CanvasColorPrefs: View {
    @AppStorage(PrefKeys.theme) private var theme: String = ThemeChoice.light.rawValue
    @Environment(AppSession.self) private var session
    @State private var colors = CanvasThemeStore.current

    private struct Role: Identifiable {
        let id: String
        let label: String
        let override: WritableKeyPath<CanvasThemeColors, String?>
        let base: KeyPath<MindMapTheme, NSColor>
    }
    private static let roles: [Role] = [
        Role(id: "paper", label: "Canvas background", override: \.paper, base: \.paperColor),
        Role(id: "rootFill", label: "Root fill", override: \.rootFill, base: \.rootFillColor),
        Role(id: "rootText", label: "Root text", override: \.rootText, base: \.rootTextColor),
        Role(id: "firstFill", label: "Level-1 fill", override: \.firstFill, base: \.firstLevelFillColor),
        Role(id: "firstText", label: "Level-1 text", override: \.firstText, base: \.firstLevelTextColor),
        Role(id: "otherFill", label: "Other fill", override: \.otherFill, base: \.otherLevelFillColor),
        Role(id: "otherText", label: "Other text", override: \.otherText, base: \.otherLevelTextColor),
        Role(id: "connector", label: "Connectors", override: \.connector, base: \.connectorColor),
    ]

    var body: some View {
        Section(L("prefs.mindmap.section.canvas_colors")) {
            if theme == ThemeChoice.custom.rawValue {
                ForEach(Self.roles) { role in
                    ColorPicker(role.label, selection: binding(for: role), supportsOpacity: false)
                }
                Button(L("prefs.editor.colors_reset")) {
                    colors = CanvasThemeColors()
                    persist()
                }
            } else {
                Text(L("prefs.mindmap.canvas_colors_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func persist() {
        CanvasThemeStore.save(colors)
        session.canvasThemeRevision &+= 1
    }

    private func binding(for role: Role) -> Binding<Color> {
        Binding(
            get: {
                let hex = colors[keyPath: role.override]
                let base = MindMapTheme.light[keyPath: role.base]
                return Color(nsColor: hex.flatMap(NSColor.init(hexString:)) ?? base)
            },
            set: { newColor in
                colors[keyPath: role.override] = NSColor(newColor).hexString
                persist()
            }
        )
    }
}

private struct AIPrefs: View {
    @AppStorage(PrefKeys.aiStreamingEnabled) private var streaming: Bool = true

    var body: some View {
        Form {
            // Provider / API key / endpoint / model — the actual AI config.
            AIProviderConfig()
            Section(L("prefs.ai.section.behavior")) {
                Toggle(L("prefs.ai.streaming"), isOn: $streaming)
            }
            RestoreDefaultsRow(group: .ai)
        }
        .formStyle(.grouped)
        .padding()
    }
}

