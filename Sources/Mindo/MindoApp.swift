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

/// Convenience: localized string lookup from the app's bundle (forwards to
/// `String(localized:bundle:)` so we can write `L("key")` everywhere).
@inline(__always) func L(_ key: String.LocalizationValue) -> String {
    return String(localized: key, bundle: .module)
}

/// AppKit delegate used to force regular-app activation when launched via
/// `swift run`. Without this, the SPM-built binary ships without the
/// LSApplicationCategoryType + .app bundle treatment, so windows open behind
/// other apps and the Dock icon is missing.
final class MindoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
                    session.persistOpenTabs()
                }
                .sheet(isPresented: $session.aiSettingsOpen) { AISettingsView() }
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
                .sheet(isPresented: $session.snippetPickerOpen) {
                    SnippetPicker(fileType: session.activeFileType) { snippet in
                        session.insertSnippet(snippet)
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
        }
        .commands {
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
                Divider()
                Button(L("menu.file.quick_open")) { session.quickSwitcherOpen = true }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(session.workspaceRoots.isEmpty)
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
                Button(L("menu.file.close_tab")) { session.closeActive() }
                    .keyboardShortcut("w", modifiers: .command)
                    .disabled(session.activeDocument == nil)
                Button(L("menu.file.print")) { session.printActiveDocument() }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(session.activeDocument == nil)
                Divider()
                Menu(L("menu.file.import")) {
                    Button(L("menu.file.import_freemind")) { session.importFreemind() }
                    Button(L("menu.file.import_text_outline")) { session.importTextOutline() }
                    Button(L("menu.file.import_mindmup")) { session.importMindmup() }
                    Button(L("menu.file.import_coggle")) { session.importCoggle() }
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
                }
                .disabled(session.activeFileType != .mindMap)
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
                }
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
                Button(L("menu.ai.generate")) { session.openAIGenerate(intent: .input) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(session.activeDocument == nil)
                Button(L("menu.ai.summarize")) { session.openAIGenerate(intent: .summarize) }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .disabled(session.activeDocument == nil)
                Button(L("menu.ai.reframe")) { session.openAIGenerate(intent: .reframe) }
                    .keyboardShortcut("r", modifiers: [.command, .control])
                    .disabled(session.activeDocument == nil)
                Divider()
                Button(L("menu.ai.settings")) { session.aiSettingsOpen = true }
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
        Settings { PreferencesView() }
    }
}

// MARK: - Session model

@Observable
final class AppSession {
    var workspaces: [WorkspaceMeta] = []
    var workspaceRoots: [NodeData] = []   // mirrors `workspaces` 1:1, lazy children
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
    var lastError: String?

    /// MRU tab tracker — drives ⌃⇥ / ⌃⇧⇥ "next/previous tab" navigation.
    @ObservationIgnored let tabManager = TabManager<OpenDocument.ID>()

    /// One per open file with a URL — reloads or marks externally-modified on writes.
    @ObservationIgnored var fileWatchers: [OpenDocument.ID: FileWatcher] = [:]
    /// One per added workspace — refreshes the sidebar tree on directory changes.
    @ObservationIgnored var workspaceWatchers: [URL: WorkspaceWatcher] = [:]

    // AI sheets
    var aiSettingsOpen: Bool = false
    var aiGenerateOpen: Bool = false
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

    /// Per-document outline navigation request. Editor views observe this and
    /// scroll/center on change. Reset to nil after a brief debounce so the
    /// same target can fire again.
    var outlineNavigationTarget: String?

    /// View > Zoom command + monotonically-increasing tick so the canvas
    /// observes any new request even when the same enum case repeats.
    enum ZoomCommand { case `in`, out, reset, fit }
    var zoomCommand: ZoomCommand = .reset
    var zoomCommandTick: UInt64 = 0

    /// View > Fold/Unfold All commands. Same tick pattern as ZoomCommand —
    /// the active mindmap canvas listens for changes and dispatches.
    enum MindmapCommand { case foldAll, unfoldAll, redraw }
    var mindmapCommand: MindmapCommand = .foldAll
    var mindmapCommandTick: UInt64 = 0

    /// Snippet picker sheet flag.
    var snippetPickerOpen: Bool = false
    /// About-Mindo sheet flag.
    var aboutOpen: Bool = false

    /// Find-in-files sheet flag.
    var findInFilesOpen: Bool = false
    /// Obsidian-style ⌘O quick switcher sheet flag.
    var quickSwitcherOpen: Bool = false

    /// Flat index of every file across open workspaces — data source for
    /// the quick switcher. Rebuilt each time the switcher opens so it
    /// reflects files added since launch.
    func quickSwitcherFiles() -> [WorkspaceFile] {
        WorkspaceFileIndex.index(
            roots: workspaceRoots.map { ($0.url, $0.name) },
            config: .fromPreferences()
        )
    }
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
