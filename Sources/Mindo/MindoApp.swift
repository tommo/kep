import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MindoCore
import MindoMindMap
import MindoBase
import MindoCSV
import MindoGenAI
import MindoMarkdown
import MindoPlantUML
import MindoModel

extension NSView {
    /// Recursive depth-first search for the first descendant of `type`
    /// matching `predicate`. Used by the zoom-command bridge above.
    func firstSubview<T: NSView>(ofType _: T.Type, where predicate: (T) -> Bool) -> T? {
        if let typed = self as? T, predicate(typed) { return typed }
        for sub in subviews {
            if let hit = sub.firstSubview(ofType: T.self, where: predicate) { return hit }
        }
        return nil
    }
}

/// The SPM resource bundle, resolved WITHOUT `Bundle.module`'s fatalError so a
/// packaging/launch quirk degrades to English keys instead of crashing the app.
/// `Bundle.module` only searches `Bundle.main.bundleURL` + the build dir; that
/// misses `Contents/Resources/Mindo_Mindo.bundle` when the binary is launched
/// directly (not via `open`), which trapped the whole app. We probe the real
/// locations and fall back to `.main`.
let mindoLocalizationBundle: Bundle = {
    let name = "Mindo_Mindo.bundle"
    let main = Bundle.main
    let exeDir = URL(fileURLWithPath: CommandLine.arguments.first ?? main.bundlePath)
        .deletingLastPathComponent()
    let candidates: [URL?] = [
        main.resourceURL?.appendingPathComponent(name),                 // Contents/Resources (open-launched)
        main.bundleURL.appendingPathComponent(name),                    // .app root / exe dir
        main.bundleURL.appendingPathComponent("Contents/Resources/\(name)"),
        exeDir.appendingPathComponent(name),                            // next to the binary
        exeDir.deletingLastPathComponent().appendingPathComponent("Resources/\(name)"), // Contents/Resources from MacOS
    ]
    for case let url? in candidates where (try? url.checkResourceIsReachable()) == true {
        if let bundle = Bundle(url: url) { return bundle }
    }
    return .main
}()

/// Convenience: localized string lookup from the app's bundle (forwards to
/// `String(localized:bundle:)` so we can write `L("key")` everywhere).
@inline(__always) func L(_ key: String.LocalizationValue) -> String {
    return String(localized: key, bundle: mindoLocalizationBundle)
}

/// AppKit delegate used to force regular-app activation when launched via
/// `swift run`. Without this, the SPM-built binary ships without the
/// LSApplicationCategoryType + .app bundle treatment, so windows open behind
/// other apps and the Dock icon is missing.
final class MindoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AppAppearance.applyCurrent()   // honor the saved Light/Dark/System override
        PreviewWebSecurity.warmUp()    // compile the remote-content block before any preview loads
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Prompt before quitting when the user opted in via Preferences.
    /// Default off (macOS expectation is `Cmd-Q quits`); the alert
    /// targets the "I keep accidentally quitting" workflow that
    /// mindolph's GENERAL_CONFIRM_BEFORE_QUITTING serves.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard PrefKeys.bool(PrefKeys.confirmBeforeQuit, fallback: false) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L("quit.confirm.title")
        alert.informativeText = L("quit.confirm.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("quit.confirm.quit"))
        alert.addButton(withTitle: L("quit.confirm.cancel"))
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

@main
struct MindoApp: App {
    @NSApplicationDelegateAdaptor(MindoAppDelegate.self) var appDelegate
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup("Mindo") {
            ContentView(session: $session)
                .frame(minWidth: 1000, minHeight: 700)
                // Persist tab state on app quit as a safety net for
                // anything the inline persistOpenTabs() calls miss.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    session.captureActiveCanvasViewState()
                    session.persistOpenTabs()
                }
                .sheet(isPresented: $session.aiGenerateOpen) {
                    AIGeneratePane(
                        context: AIGeneratePane.Context(
                            supportedModes: session.aiSupportedModes,
                            defaultPrompt: session.aiDefaultPrompt
                        )
                    ) { text, mode in
                        session.applyAIResult(text: text, mode: mode)
                    }
                }
                .sheet(isPresented: $session.luaRunnerOpen) {
                    LuaRunnerView(session: $session)
                }
                .sheet(isPresented: $session.snippetPickerOpen) {
                    SnippetPicker(fileType: session.activeFileType) { snippet in
                        session.insertSnippet(snippet)
                    }
                }
                .sheet(isPresented: $session.plantUMLTemplatePickerOpen) {
                    PlantUMLTemplatePicker { template in
                        session.createPlantUML(from: template)
                    }
                }
                .sheet(isPresented: $session.findInFilesOpen) {
                    NavigationStack {
                        FindInFilesPanel(workspaceRoots: session.workspaceRoots.map(\.url)) { url, hit in
                            // Extract the actual matched substring from the
                            // hit so the canvas can tint topics carrying it.
                            session.lastSearchMatch = hit.matchedSubstring
                            session.open(url: url)
                            session.findInFilesOpen = false
                        }
                        .frame(minWidth: 560, minHeight: 420)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { session.findInFilesOpen = false }
                            }
                        }
                    }
                }
                .sheet(isPresented: $session.aboutOpen) { AboutView() }
                .sheet(isPresented: $session.quickSwitcherOpen) {
                    QuickSwitcherView(
                        files: session.quickSwitcherFiles(),
                        onOpen: { url in session.open(url: url) },
                        onClose: { session.quickSwitcherOpen = false }
                    )
                }
                .sheet(isPresented: $session.commandPaletteOpen) {
                    CommandPaletteView(
                        commands: session.paletteCommands(),
                        onClose: { session.commandPaletteOpen = false }
                    )
                }
                .sheet(isPresented: $session.nodeJumpOpen) {
                    NodeJumpView(
                        items: session.outlineItems,
                        onSelect: { target in session.requestOutlineNavigation(target: target) },
                        onClose: { session.nodeJumpOpen = false }
                    )
                }
        }
        .commands {
            // Close Tab (⌘W) — scoped to the document window via a focused scene
            // value, so it's INACTIVE when the Settings window is key (⌘W then
            // closes Settings natively instead of tearing down the document).
            DocumentCloseCommands(close: { session.closeActive() })
            CommandGroup(replacing: .appInfo) {
                Button(L("menu.help.about")) { session.aboutOpen = true }
            }
            CommandGroup(replacing: .help) {
                Button(L("menu.help.releases")) {
                    if let url = URL(string: ReleaseChecker.releasesPageURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button(L("menu.file.new_mindmap")) { session.newMindMap() }
                    .keyboardShortcut("n", modifiers: .command)
                Button(L("menu.file.new_markdown")) { session.newMarkdown() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button(L("menu.file.new_csv")) { session.newCSV() }
                Button(L("menu.file.new_plantuml")) { session.newPlantUML() }
                Button(L("menu.file.new_notebook")) { session.newResearchNotebook() }
                Button(L("menu.file.new_text")) { session.newTextFile() }
                Divider()
                Button(L("menu.file.quick_open")) { session.quickSwitcherOpen = true }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(session.workspaceRoots.isEmpty)
                Button(L("menu.file.command_palette")) { session.commandPaletteOpen = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button(L("menu.file.goto_node")) { session.nodeJumpOpen = true }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(session.activeFileType != .mindMap)
                Button(L("menu.file.open_workspace")) { session.openWorkspace() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button(L("menu.file.open_file")) { session.openFile() }
                    .keyboardShortcut("o", modifiers: [.command, .option])
                Button(L("menu.file.save")) { session.saveActive() }
                    .keyboardShortcut("s", modifiers: .command)
                Button(L("menu.file.save_as")) { session.saveActiveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button(L("menu.file.save_all")) { session.saveAllDirty() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(!session.hasDirtyOpenDocuments)
                Button(L("menu.file.print")) { session.printActiveDocument() }
                    .disabled(session.activeDocument == nil)
                Divider()
                Menu(L("menu.file.import")) {
                    Button(L("menu.file.import_freemind")) { session.importFreemind() }
                    Button(L("menu.file.import_text_outline")) { session.importTextOutline() }
                    Button(L("menu.file.import_mindmup")) { session.importMindmup() }
                    Button(L("menu.file.import_coggle")) { session.importCoggle() }
                    Button(L("menu.file.import_xmind")) { session.importXMind() }
                    Button(L("menu.file.import_novamind")) { session.importNovamind() }
                }
                Divider()
                Menu(L("menu.file.open_recent")) {
                    let recents = CollectionStore.shared.recents
                    if recents.isEmpty {
                        Text(L("menu.file.open_recent.empty")).disabled(true)
                    } else {
                        ForEach(recents, id: \.path) { entry in
                            Button(URL(fileURLWithPath: entry.path).lastPathComponent) {
                                session.open(url: entry.url)
                            }
                        }
                        Divider()
                        Button(L("menu.file.clear_recents")) { session.clearRecents() }
                    }
                }
                Menu(L("menu.file.collections")) {
                    Button(L("menu.file.save_tabs_as_collection")) {
                        session.saveActiveTabsAsCollection()
                    }
                    .disabled(session.openDocuments.isEmpty)
                    let cols = CollectionStore.shared.collections
                    if !cols.isEmpty {
                        Divider()
                        ForEach(cols) { col in
                            Button(col.name) { session.openCollection(col) }
                        }
                    }
                }
                Menu(L("menu.file.export")) {
                    Button(L("menu.file.export_markdown_html")) { Task { await session.exportActiveAsHTML() } }
                        .disabled(!session.activeIsMarkdown)
                    Button(L("menu.file.export_markdown_pdf")) { Task { await session.exportActiveAsPDF() } }
                        .disabled(!session.activeIsMarkdown)
                    Button(L("menu.file.export_freemind")) { session.exportActiveAsFreeMind() }
                        .disabled(session.activeFileType != .mindMap)
                    Button(L("menu.file.export_mindmap_png")) { session.exportActiveAsPNG() }
                        .disabled(session.activeFileType != .mindMap)
                    Button(L("menu.file.export_mindmap_svg")) { session.exportActiveAsSVG() }
                        .disabled(session.activeFileType != .mindMap)
                    Button(L("menu.file.export_mindmap_pdf")) { session.exportActiveMindmapAsPDF() }
                        .disabled(session.activeFileType != .mindMap)
                    Button(L("menu.file.export_mindmap_orgmode")) { session.exportActiveAsOrgMode() }
                        .disabled(session.activeFileType != .mindMap)
                    Button(L("menu.file.export_mindmap_markdown")) { session.exportActiveAsMarkdown() }
                        .disabled(session.activeFileType != .mindMap)
                    Button(L("menu.file.export_mindmap_asciidoc")) { session.exportActiveAsAsciiDoc() }
                        .disabled(session.activeFileType != .mindMap)
                    Button(L("menu.file.export_mindmap_mindmup")) { session.exportActiveAsMindmup() }
                        .disabled(session.activeFileType != .mindMap)
                }
            }
            CommandGroup(after: .pasteboard) {
                Menu(L("menu.edit.copy_mindmap_as")) {
                    Button(L("menu.edit.copy_mindmap_as_markdown")) { session.copyActiveMindmapAsMarkdown() }
                    Button(L("menu.edit.copy_mindmap_as_text"))     { session.copyActiveMindmapAsText() }
                    Button(L("menu.edit.copy_mindmap_as_asciidoc")) { session.copyActiveMindmapAsAsciiDoc() }
                    Button(L("menu.edit.copy_mindmap_as_orgmode"))  { session.copyActiveMindmapAsOrgMode() }
                    Divider()
                    Button(L("menu.edit.copy_mindmap_as_png")) { session.copyActiveMindmapAsPNG() }
                    Button(L("menu.edit.copy_mindmap_as_svg")) { session.copyActiveMindmapAsSVG() }
                }
                .disabled(session.activeFileType != .mindMap)
                Button(L("menu.edit.copy_markdown_as_html")) { session.copyActiveMarkdownAsHTML() }
                    .disabled(session.activeFileType != .markdown)
                Button(L("menu.edit.find")) { session.invokeFindInActiveDocument() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(session.activeDocument == nil)
                Button(L("menu.edit.insert_snippet")) { session.snippetPickerOpen = true }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                    .disabled(session.activeDocument == nil)
                Button(L("menu.edit.find_in_files")) { session.findInFilesOpen = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(session.workspaceRoots.isEmpty)
            }
            CommandMenu(L("menu.view.theme")) {
                Picker(L("menu.view.theme"), selection: $session.theme) {
                    Text(L("menu.view.theme.light")).tag(ThemeChoice.light)
                    Text(L("menu.view.theme.dark")).tag(ThemeChoice.dark)
                    Text(L("menu.view.theme.classic")).tag(ThemeChoice.classic)
                    Text(L("menu.view.theme.custom")).tag(ThemeChoice.custom)
                }
                Divider()
                Button(session.sidebarVisible ? L("menu.view.hide_sidebar") : L("menu.view.show_sidebar")) {
                    session.sidebarVisible.toggle()
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                Divider()
                Button(L("menu.view.focus_tree")) { session.focusRegion(.sidebar) }
                    .keyboardShortcut("1", modifiers: .command)
                Button(L("menu.view.focus_document")) { session.focusRegion(.document) }
                    .keyboardShortcut("2", modifiers: .command)
                Button(L("menu.view.focus_inspector")) { session.focusRegion(.inspector) }
                    .keyboardShortcut("3", modifiers: .command)
                Button(L("menu.view.focus_agent")) { session.focusRegion(.agent) }
                    .keyboardShortcut("\\", modifiers: .command)
                Divider()
                Button(L("menu.view.zoom_in")) { session.zoomCommand = .in; session.zoomCommandTick &+= 1 }
                    .keyboardShortcut("=", modifiers: .command)
                Button(L("menu.view.zoom_out")) { session.zoomCommand = .out; session.zoomCommandTick &+= 1 }
                    .keyboardShortcut("-", modifiers: .command)
                Button(L("menu.view.reset_zoom")) { session.zoomCommand = .reset; session.zoomCommandTick &+= 1 }
                    .keyboardShortcut("0", modifiers: .command)
                Button(L("menu.view.zoom_to_fit")) { session.zoomCommand = .fit; session.zoomCommandTick &+= 1 }
                    .keyboardShortcut("9", modifiers: .command)
                Divider()
                Button(L("menu.view.fold_all")) { session.mindmapCommand = .foldAll; session.mindmapCommandTick &+= 1 }
                    .keyboardShortcut("[", modifiers: [.command, .option])
                    .disabled(session.activeFileType != .mindMap)
                Button(L("menu.view.unfold_all")) { session.mindmapCommand = .unfoldAll; session.mindmapCommandTick &+= 1 }
                    .keyboardShortcut("]", modifiers: [.command, .option])
                    .disabled(session.activeFileType != .mindMap)
                Divider()
                Toggle(L("menu.view.show_jump_arrows"), isOn: Binding(
                    get: { PrefKeys.bool(PrefKeys.showJumpArrows, fallback: true) },
                    set: { newValue in
                        UserDefaults.standard.set(newValue, forKey: PrefKeys.showJumpArrows)
                        session.mindmapCommand = .redraw
                        session.mindmapCommandTick &+= 1
                    }
                ))
                .disabled(session.activeFileType != .mindMap)
            }
            CommandMenu(L("menu.ai")) {
                Button("Assistant") {
                    session.outlineOpen = true
                    session.inspectorTab = .agent
                }
                .keyboardShortcut("a", modifiers: [.command, .control])
                Divider()
                Button(L("menu.ai.generate")) { session.openAIGenerate(intent: .input) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(session.activeDocument == nil)
                Button(L("menu.ai.summarize")) { session.openAIGenerate(intent: .summarize) }
                    .keyboardShortcut("u", modifiers: [.command, .control])
                    .disabled(session.activeDocument == nil)
                Button(L("menu.ai.reframe")) { session.openAIGenerate(intent: .reframe) }
                    .keyboardShortcut("r", modifiers: [.command, .control])
                    .disabled(session.activeDocument == nil)
                Divider()
                Button("Run Lua Script…") { session.luaRunnerOpen = true }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(session.activeFileType != .mindMap)
                Divider()
                SettingsLink { Text(L("menu.ai.settings")) }
                    .keyboardShortcut(",", modifiers: [.command, .shift])
            }
            CommandMenu("Window") {
                Button(L("menu.window.next_tab")) { session.cycleNextTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(session.openDocuments.count < 2)
                Button(L("menu.window.previous_tab")) { session.cyclePreviousTab() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(session.openDocuments.count < 2)
                Divider()
                Button(L(session.outlineOpen ? "menu.window.hide_outline" : "menu.window.show_outline")) {
                    session.outlineOpen.toggle()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }
        // Settings is a separate scene, so it doesn't inherit the main window's
        // environment — inject the session explicitly or PreferencesView's
        // @Environment(AppSession.self) crashes ("No Observable object…").
        Settings { PreferencesView().environment(session) }
    }
}

// MARK: - Document-scoped commands

/// Set by the document window's content; absent when another scene (e.g. the
/// Settings window) is key. Used to scope ⌘W to documents.
private struct DocumentSceneActiveKey: FocusedValueKey { typealias Value = Bool }
extension FocusedValues {
    var documentSceneActive: Bool? {
        get { self[DocumentSceneActiveKey.self] }
        set { self[DocumentSceneActiveKey.self] = newValue }
    }
}

/// The File ▸ Close Tab (⌘W) command, enabled only while a document scene is
/// focused. When the Settings window is key the focused value is nil, so this
/// command is disabled and ⌘W falls through to AppKit's native window close.
private struct DocumentCloseCommands: Commands {
    @FocusedValue(\.documentSceneActive) private var documentActive
    let close: () -> Void
    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button(L("menu.file.close_tab"), action: close)
                .keyboardShortcut("w", modifiers: .command)
                .disabled(documentActive != true)
        }
    }
}

// MARK: - Session model

@Observable
final class AppSession {
    var workspaces: [WorkspaceMeta] = []
    var workspaceRoots: [NodeData] = []   // mirrors `workspaces` 1:1, lazy children
    /// Bumped whenever a workspace's children are reloaded. NodeData is a
    /// reference type SwiftUI doesn't observe, so reloading a root in place
    /// doesn't redraw rows; the sidebar `.id`s its list on this token to rebuild.
    var sidebarReloadToken = 0
    var openDocuments: [OpenDocument] = []
    var activeDocumentID: OpenDocument.ID? {
        didSet {
            // Autosave the doc we just left — silent, only if it has a URL
            // and is dirty. Skipped when the change is a no-op.
            if let prev = oldValue, prev != activeDocumentID {
                autosaveDocument(id: prev)
            }
            if let id = activeDocumentID { tabManager.activate(id) }
        }
    }
    var theme: ThemeChoice = ThemeChoice(rawValue:
        UserDefaults.standard.string(forKey: PrefKeys.theme) ?? ""
    ) ?? .light
    /// Bumped when the custom canvas colors change so the canvas re-renders
    /// even though the ThemeChoice (.custom) itself is unchanged.
    var canvasThemeRevision = 0
    var lastError: String?

    /// MRU tab tracker — drives ⌃⇥ / ⌃⇧⇥ "next/previous tab" navigation.
    @ObservationIgnored let tabManager = TabManager<OpenDocument.ID>()

    /// One per open file with a URL — reloads or marks externally-modified on writes.
    @ObservationIgnored var fileWatchers: [OpenDocument.ID: FileWatcher] = [:]
    /// One per added workspace — refreshes the sidebar tree on directory changes.
    @ObservationIgnored var workspaceWatchers: [URL: WorkspaceWatcher] = [:]

    /// Monotonic counter bumped on any workspace file change (add/remove/rename
    /// via reloadWorkspace, plus content writes seen by the workspace watcher).
    /// Keys the file-index / backlink caches below so they recompute only when
    /// the corpus actually changed — not on every view re-render or autocomplete
    /// keystroke. ObservationIgnored: bumping it must not itself invalidate views
    /// (the watcher already re-publishes workspaceRoots).
    @ObservationIgnored var workspaceContentVersion = 0
    /// Cached workspace file index (the FS walk in `quickSwitcherFiles`).
    @ObservationIgnored private var fileIndexCache: (version: Int, files: [WorkspaceFile])?
    /// Cached linked-mentions for the active doc, keyed by target + version.
    @ObservationIgnored private var linkedMentionsCache: (key: String, value: [LinkedMention])?

    // AI sheets
    var aiSettingsOpen: Bool = false
    var aiGenerateOpen: Bool = false
    /// Which surface the right inspector shows — document outline or AI assistant.
    var inspectorTab: InspectorTab = .inspector
    /// The window region with keyboard focus (drives the focus-ring indicator).
    var activeRegion: AppSession.FocusRegion?
    /// Region container views (tagged from ContentView via RegionContainerTagger)
    /// + the event monitor that keeps `activeRegion` in sync with the REAL first
    /// responder. Without this the highlight only tracked ⌘1/2/3; now clicking
    /// (or Tab-ing) into a pane moves it too. See [[feedback_keyboard_only_ux]].
    @ObservationIgnored var regionContainers: [FocusRegion: WeakViewBox] = [:]
    @ObservationIgnored var regionFocusMonitor: Any?
    var aiSupportedModes: [AIGeneratePane.InsertionMode] = [.append]
    var aiDefaultPrompt: String = ""

    /// Whether the right-hand outline inspector is showing. Seeded from
    /// PrefKeys so the user's "show outline by default" choice sticks.
    var outlineOpen: Bool = PrefKeys.bool(PrefKeys.outlineOpenByDefault, fallback: true)

    /// File-type filter for the workspace sidebar. Empty = no filter (all
    /// files visible). Folders always show regardless so the user can
    /// navigate. Mirrors Mindolph's `FileFilterButtonGroup`.
    var sidebarTypeFilter: Set<SupportedFileType> = []

    /// Most recent text matched by a Find-in-Files hit. The mindmap canvas
    /// reads this and tints any topic whose title contains the query, so
    /// the user immediately sees which topic produced the result.
    /// Cleared on next selection / new doc open.
    var lastSearchMatch: String?

    /// ID of the workspace tree row currently in inline-rename mode.
    /// `nil` means no row is being renamed. Cleared on commit/cancel.
    var renamingNodeID: UUID?

    /// One-shot: whether the next-opened editor may grab keyboard focus. A
    /// browse-open (sidebar single-click) sets this false so focus stays in the
    /// sidebar; `consumeFocusOnOpen()` reads and resets it to true.
    var pendingEditorFocus = true

    /// Per-document outline navigation request. Editor views observe this and
    /// scroll/center on change. Reset to nil after a brief debounce so the
    /// same target can fire again.
    var outlineNavigationTarget: String?

    /// The outline index-path of the topic currently selected in the mind-map
    /// canvas. Published by the canvas on selection change so the outline panel
    /// highlights the matching row (graph → outline selection sync).
    var selectedOutlineTarget: String?

    /// View > Zoom command + monotonically-increasing tick so the canvas
    /// observes any new request even when the same enum case repeats.
    enum ZoomCommand { case `in`, out, reset, fit }
    var zoomCommand: ZoomCommand = .reset
    var zoomCommandTick: UInt64 = 0

    /// View > Fold/Unfold All commands. Same tick pattern as ZoomCommand —
    /// the active mindmap canvas listens for changes and dispatches.
    enum MindmapCommand { case foldAll, unfoldAll, redraw, reload }
    var mindmapCommand: MindmapCommand = .foldAll
    var mindmapCommandTick: UInt64 = 0
    /// Lua script runner sheet flag.
    var luaRunnerOpen: Bool = false

    /// Snippet picker sheet flag.
    var snippetPickerOpen: Bool = false
    var plantUMLTemplatePickerOpen: Bool = false
    /// About-Mindo sheet flag.
    var aboutOpen: Bool = false

    /// Find-in-files sheet flag.
    var findInFilesOpen: Bool = false
    /// Obsidian-style ⌘O quick switcher sheet flag.
    var quickSwitcherOpen: Bool = false
    /// Obsidian-style ⌘⇧P command palette sheet flag.
    var commandPaletteOpen: Bool = false
    /// "Go to Node" (⌘P) sheet flag — search the active mind map's topics.
    var nodeJumpOpen: Bool = false

    /// Flat index of every file across open workspaces — data source for
    /// the quick switcher. Rebuilt each time the switcher opens so it
    /// reflects files added since launch.
    func quickSwitcherFiles() -> [WorkspaceFile] {
        if let cache = fileIndexCache, cache.version == workspaceContentVersion {
            return cache.files
        }
        let files = WorkspaceFileIndex.index(
            roots: workspaceRoots.map { ($0.url, $0.name) },
            config: .fromPreferences()
        )
        fileIndexCache = (workspaceContentVersion, files)
        return files
    }

    /// Workspace file URLs + their text (the KB corpus) — shared by backlinks,
    /// the Lua runner, and the agent loop (best-effort; unreadable files drop).
    func workspaceCorpus() -> (files: [URL], corpus: [(url: URL, text: String)]) {
        let files = quickSwitcherFiles().map(\.url)
        let corpus: [(url: URL, text: String)] = files.compactMap { u in
            (try? String(contentsOf: u, encoding: .utf8)).map { (u, $0) }
        }
        return (files, corpus)
    }

    /// Resolve a clicked `[[wiki link]]` target to a workspace document and open
    /// it. Heading navigation is best-effort (v0 opens the doc). Surfaces an
    /// error when nothing resolves.
    func openWikiLink(target: String, heading: String?) {
        let files = quickSwitcherFiles().map(\.url)
        guard let url = WikiLinkResolver.resolve(target, in: files) else {
            lastError = "No workspace document matches “\(target)”."
            return
        }
        open(url: url)
        // Scroll to the heading, if the link named one and the doc is markdown.
        if let heading, !heading.isEmpty,
           case .text(let text, .markdown)? = activeDocument?.kind,
           let offset = MarkdownHeadingIndex.byteOffset(forHeading: heading, in: text) {
            requestOutlineNavigation(target: String(offset))
        }
    }

    /// Distinct workspace document base names (no extension), for `[[wiki link]]`
    /// autocomplete in the markdown editor — the resolver matches links by base
    /// name, so the names offered mirror what a click would resolve.
    func wikiLinkDocumentNames() -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for file in quickSwitcherFiles() {
            let name = file.url.deletingPathExtension().lastPathComponent
            if !name.isEmpty, seen.insert(name.lowercased()).inserted { names.append(name) }
        }
        return names
    }

    /// "Linked mentions" for the active document: every workspace doc that
    /// references it via a [[wiki link]], with the context line of each mention.
    /// Reads the workspace corpus on demand (workspaces are small). Empty when
    /// the active doc is unsaved or nothing links to it.
    func linkedMentions() -> [LinkedMention] {
        guard let target = activeDocument?.fileURL else { return [] }
        // linksInspector reads this during view-body evaluation, which can fire
        // many times per interaction; the body re-reads the whole workspace
        // corpus from disk. Memoize per (target, corpus-version) so it only
        // does the disk pass when the active doc or the corpus changes.
        let key = "\(target.path)#\(workspaceContentVersion)"
        if let cache = linkedMentionsCache, cache.key == key { return cache.value }
        let (files, corpus) = workspaceCorpus()
        let result = Backlinks.mentions(to: target, corpus: corpus, allFiles: files)
        linkedMentionsCache = (key, result)
        return result
    }
    /// Whether the sidebar column is shown. Persisted (PrefKeys.sidebarVisible)
    /// so collapse state survives relaunch. Toggled from the View menu (⌃⌘S).
    var sidebarVisible: Bool = PrefKeys.bool(PrefKeys.sidebarVisible, fallback: true) {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: PrefKeys.sidebarVisible) }
    }

    /// Per-folder expansion state the user has toggled, restored across
    /// launches so the workspace tree reopens the way it was left.
    var sidebarExpansion: [String: Bool] = SidebarExpansionState.decode(
        PrefKeys.string(PrefKeys.sidebarExpansion))

    /// Whether `url`'s folder row should render expanded. Workspaces default
    /// open, sub-folders closed, until the user toggles them.
    func isFolderExpanded(_ url: URL, isWorkspace: Bool) -> Bool {
        SidebarExpansionState.isExpanded(url.path, in: sidebarExpansion, defaultExpanded: isWorkspace)
    }

    /// Record a folder's expansion and persist the whole map.
    func setFolderExpanded(_ url: URL, isWorkspace: Bool, _ expanded: Bool) {
        sidebarExpansion[url.path] = expanded
        UserDefaults.standard.set(SidebarExpansionState.encode(sidebarExpansion),
                                  forKey: PrefKeys.sidebarExpansion)
    }

    /// Native CSV find/replace bar visible (CSV editor only — its
    /// NSTableView can't use the standard text find bar). Toggled by ⌘F.
    var csvFindOpen: Bool = false
    /// In-document Find bar visible (mindmap canvas only — text editors
    /// route ⌘F to NSTextView's built-in find bar).
    var inDocFindOpen: Bool = false

    /// Outline rows for the currently active document. Recomputed lazily on read.
    var outlineItems: [OutlineItem] { activeDocument?.outlineItems ?? [] }

    init() {
        let mgr = WorkspaceManager.shared
        mgr.removeNonExistentWorkspaces()
        self.workspaces = mgr.list.projects
        self.workspaceRoots = workspaces.map { mgr.loadTree(for: $0) }
        self.workspaceRoots.forEach { startWorkspaceWatcher(for: $0) }
        // Re-open the tabs that were open when the app last quit.
        restoreOpenTabs()
        // Save dirty docs whenever any window loses key — covers ⌘Tab to
        // another app, switching to another Mindo window, etc.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.autosaveAllDirty() }
    }

    // All AppSession behavior beyond stored properties + init lives in
    // Sources/Mindo/Session/AppSession+*.swift extensions:
    //   • Workspaces.swift    — open/add/remove + workspace watcher install
    //   • Documents.swift     — open(url:)/close/new + file watcher
    //   • Save.swift          — save / saveAs / export HTML+PDF
    //   • Collections.swift   — Collections + Open Recent
    //   • AI.swift            — openAIGenerate + applyAIResult
    //   • Helpers.swift       — outline nav, active-doc accessors, snippets
}
