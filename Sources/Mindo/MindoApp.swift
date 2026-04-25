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
}

@main
struct MindoApp: App {
    @NSApplicationDelegateAdaptor(MindoAppDelegate.self) var appDelegate
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup("Mindo") {
            ContentView(session: $session)
                .frame(minWidth: 1000, minHeight: 700)
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
                        FindInFilesPanel(workspaceRoots: session.workspaceRoots.map(\.url)) { url, _ in
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
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("menu.file.new_mindmap")) { session.newMindMap() }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button(L("menu.file.open_workspace")) { session.openWorkspace() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button(L("menu.file.open_file")) { session.openFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Button(L("menu.file.save")) { session.saveActive() }
                    .keyboardShortcut("s", modifiers: .command)
                Button(L("menu.file.save_as")) { session.saveActiveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button(L("menu.file.close_tab")) { session.closeActive() }
                    .keyboardShortcut("w", modifiers: .command)
                    .disabled(session.activeDocument == nil)
                Divider()
                Button(L("menu.file.import_freemind")) { session.importFreemind() }
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
                }
            }
            CommandGroup(after: .pasteboard) {
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
            }
            CommandMenu(L("menu.ai")) {
                Button(L("menu.ai.generate")) { session.openAIGenerate() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
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
            if let id = activeDocumentID { tabManager.activate(id) }
        }
    }
    var theme: ThemeChoice = .light
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

    /// Whether the right-hand outline inspector is showing.
    var outlineOpen: Bool = true

    /// Per-document outline navigation request. Editor views observe this and
    /// scroll/center on change. Reset to nil after a brief debounce so the
    /// same target can fire again.
    var outlineNavigationTarget: String?

    /// View > Zoom command + monotonically-increasing tick so the canvas
    /// observes any new request even when the same enum case repeats.
    enum ZoomCommand { case `in`, out, reset }
    var zoomCommand: ZoomCommand = .reset
    var zoomCommandTick: UInt64 = 0

    /// Snippet picker sheet flag.
    var snippetPickerOpen: Bool = false

    /// Find-in-files sheet flag.
    var findInFilesOpen: Bool = false

    /// Outline rows for the currently active document. Recomputed lazily on read.
    var outlineItems: [OutlineItem] {
        guard let doc = activeDocument else { return [] }
        switch doc.kind {
        case .mindMap(let map): return Outline.fromMindMap(map)
        case .text(let body, .markdown): return Outline.fromMarkdown(body)
        case .text(let body, .plantUML): return Outline.fromMarkdown(body) // best-effort: treat ' some title' lines if present
        case .text, .unsupported: return []
        }
    }

    init() {
        let mgr = WorkspaceManager.shared
        mgr.removeNonExistentWorkspaces()
        self.workspaces = mgr.list.projects
        self.workspaceRoots = workspaces.map { mgr.loadTree(for: $0) }
        self.workspaceRoots.forEach { startWorkspaceWatcher(for: $0) }
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

// Old method bodies retained below for the in-progress split — to be
// removed once the extensions take over. Wrap in a stale type so they
// don't double-declare.

// MARK: - Open document

struct OpenDocument: Identifiable, Hashable {
    enum Kind {
        case mindMap(MindMap)
        case text(String, fileType: SupportedFileType?)
        case unsupported(String)

        var preferredExtension: String? {
            switch self {
            case .mindMap: return "mmd"
            case .text(_, let t): return t?.rawValue
            case .unsupported: return nil
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var fileURL: URL?
    var title: String
    /// Set when the file watcher detected an external write since we last
    /// reloaded. UI shows an orange dot on the tab.
    var hasExternalChanges: Bool = false

    static func load(from url: URL) throws -> OpenDocument {
        let title = url.lastPathComponent
        let type = SupportedFileType.classify(url: url)
        switch type {
        case .mindMap:
            let text = try String(contentsOf: url, encoding: .utf8)
            let map = try MindMap(text: text)
            return OpenDocument(kind: .mindMap(map), fileURL: url, title: title)
        case .markdown, .plantUML, .csv, .plainText:
            let text = try String(contentsOf: url, encoding: .utf8)
            return OpenDocument(kind: .text(text, fileType: type), fileURL: url, title: title)
        case .jpeg, .png, .none:
            return OpenDocument(kind: .unsupported(url.path), fileURL: url, title: title)
        }
    }

    func save(to url: URL) throws {
        switch kind {
        case .mindMap(let map):
            try map.write().write(to: url, atomically: true, encoding: .utf8)
        case .text(let s, _):
            try s.write(to: url, atomically: true, encoding: .utf8)
        case .unsupported:
            break
        }
    }

    static func == (lhs: OpenDocument, rhs: OpenDocument) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum ThemeChoice: String, CaseIterable, Hashable {
    case light, dark, classic
    var theme: MindMapTheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .classic: return .classic
        }
    }
}

// MARK: - Content view

struct ContentView: View {
    @Binding var session: AppSession
    @State private var sidebarSelection: NodeData?

    var body: some View {
        NavigationSplitView {
            SidebarView(session: $session, selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 280)
        } detail: {
            DetailArea(session: $session)
                .inspector(isPresented: $session.outlineOpen) {
                    OutlinePanel(items: session.outlineItems) { item in
                        session.requestOutlineNavigation(target: item.target)
                    }
                    .navigationTitle(L("detail.outline.title"))
                    .inspectorColumnWidth(min: 220, ideal: 260, max: 380)
                }
        }
        .onChange(of: sidebarSelection) { _, new in
            if let node = new, node.isFile {
                session.open(url: node.url)
            }
        }
        .alert(L("error.alert_title"), isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("OK") { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}

// SidebarView, NodeRow, DetailArea, DocumentTabBar, and EditorPane have
// moved to Sources/Mindo/Views/*.swift to keep this file focused on the
// App entry, AppSession, and the menu commands.
