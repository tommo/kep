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
            }
            CommandMenu(L("menu.view.theme")) {
                Picker(L("menu.view.theme"), selection: $session.theme) {
                    Text(L("menu.view.theme.light")).tag(ThemeChoice.light)
                    Text(L("menu.view.theme.dark")).tag(ThemeChoice.dark)
                    Text(L("menu.view.theme.classic")).tag(ThemeChoice.classic)
                }
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
    @ObservationIgnored private var fileWatchers: [OpenDocument.ID: FileWatcher] = [:]
    /// One per added workspace — refreshes the sidebar tree on directory changes.
    @ObservationIgnored private var workspaceWatchers: [URL: WorkspaceWatcher] = [:]

    // AI sheets
    var aiSettingsOpen: Bool = false
    var aiGenerateOpen: Bool = false
    var aiSupportedModes: [AIGeneratePane.InsertionMode] = [.append]
    var aiDefaultPrompt: String = ""

    /// Whether the right-hand outline inspector is showing.
    var outlineOpen: Bool = true

    /// Snippet picker sheet flag.
    var snippetPickerOpen: Bool = false

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

    private func startWorkspaceWatcher(for node: NodeData) {
        guard workspaceWatchers[node.url] == nil else { return }
        let watcher = WorkspaceWatcher(url: node.url) { [weak self, weak node] _ in
            guard let self, let node else { return }
            // FSEvents fires bursts; coalesced 500ms inside the watcher.
            // We refresh from root because per-path delta would require
            // mapping changed paths to NodeData instances; the tree's
            // lazy children + identity-by-URL keeps this cheap.
            node.reloadChildren()
            // Trigger the @Observable to re-publish.
            self.workspaceRoots = self.workspaceRoots
        }
        watcher.start()
        workspaceWatchers[node.url] = watcher
    }

    private func stopWorkspaceWatcher(for url: URL) {
        workspaceWatchers[url]?.stop()
        workspaceWatchers.removeValue(forKey: url)
    }

    var activeDocument: OpenDocument? {
        guard let id = activeDocumentID else { return nil }
        return openDocuments.first { $0.id == id }
    }

    // MARK: - Workspaces

    func openWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addWorkspace(url: url)
    }

    func addWorkspace(url: URL) {
        let mgr = WorkspaceManager.shared
        let meta = mgr.add(workspaceAt: url)
        workspaces = mgr.list.projects
        if !workspaceRoots.contains(where: { $0.url == url }) {
            let node = mgr.loadTree(for: meta)
            workspaceRoots.append(node)
            startWorkspaceWatcher(for: node)
        }
    }

    func removeWorkspace(_ root: NodeData) {
        let mgr = WorkspaceManager.shared
        let meta = WorkspaceMeta(url: root.url)
        mgr.remove(meta)
        workspaces = mgr.list.projects
        workspaceRoots.removeAll { $0.url == root.url }
        stopWorkspaceWatcher(for: root.url)
    }

    // MARK: - Document open / close

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        if let existing = openDocuments.first(where: { $0.fileURL == url }) {
            activeDocumentID = existing.id
            return
        }
        do {
            let doc = try OpenDocument.load(from: url)
            openDocuments.append(doc)
            activeDocumentID = doc.id
            startFileWatcher(for: doc)
        } catch {
            lastError = String(format: L("error.open_failed"), error.localizedDescription)
        }
    }

    private func startFileWatcher(for doc: OpenDocument) {
        guard let url = doc.fileURL else { return }
        let id = doc.id
        let watcher = FileWatcher(url: url) { [weak self] event in
            guard let self else { return }
            self.handleFileWatcherEvent(event, for: id)
        }
        if watcher.start() { fileWatchers[id] = watcher }
    }

    private func handleFileWatcherEvent(_ event: DispatchSource.FileSystemEvent, for id: OpenDocument.ID) {
        guard let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        if event.contains(.delete) || event.contains(.rename) {
            openDocuments[idx].hasExternalChanges = true
            return
        }
        // Plain write — pull the new content into the existing document slot.
        // Keep the same OpenDocument.id so tab routing + watcher mapping
        // stay valid. We don't yet thread editor dirty-state up to the
        // App layer, so the reload always wins; the orange dot still
        // surfaces the fact that an external write happened.
        openDocuments[idx].hasExternalChanges = true
        guard let url = openDocuments[idx].fileURL,
              let reloaded = try? OpenDocument.load(from: url) else { return }
        openDocuments[idx].kind = reloaded.kind
        openDocuments[idx].title = reloaded.title
    }

    private func stopFileWatcher(for id: OpenDocument.ID) {
        fileWatchers[id]?.stop()
        fileWatchers.removeValue(forKey: id)
    }

    /// True when the active document is a markdown text doc (powers Export menu enabling).
    var activeIsMarkdown: Bool {
        guard let doc = activeDocument else { return false }
        if case .text(_, .markdown) = doc.kind { return true }
        return false
    }

    /// Pull the active doc's markdown text and write it as standalone HTML.
    @MainActor
    func exportActiveAsHTML() async {
        guard let doc = activeDocument, case .text(let body, .markdown) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "html") ?? .data]
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MarkdownExporter.exportHTML(markdown: body, to: url)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }

    /// Render the active doc's markdown to PDF via the offscreen WKWebView.
    @MainActor
    func exportActiveAsPDF() async {
        guard let doc = activeDocument, case .text(let body, .markdown) = doc.kind else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "pdf") ?? .data]
        panel.nameFieldStringValue = (doc.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await MarkdownExporter.exportPDF(markdown: body, to: url)
        } catch {
            lastError = String(format: L("error.save_failed"), error.localizedDescription)
        }
    }

    /// Open a FreeMind/Freeplane .mm file via NSOpenPanel, parse it, and present
    /// it as a fresh in-memory mindmap document (no fileURL, so Save will
    /// prompt for a .mmd path).
    func importFreemind() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "mm") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let xml = try String(contentsOf: url, encoding: .utf8)
            let map = try FreemindImporter.parse(xml)
            let title = url.deletingPathExtension().lastPathComponent + ".mmd"
            let doc = OpenDocument(kind: .mindMap(map), fileURL: nil, title: title)
            openDocuments.append(doc)
            activeDocumentID = doc.id
        } catch {
            lastError = String(format: L("error.open_failed"), error.localizedDescription)
        }
    }

    func newMindMap() {
        let map = MindMap()
        map.root = Topic(text: "New Mind Map")
        let doc = OpenDocument(kind: .mindMap(map), fileURL: nil, title: "Untitled.mmd")
        openDocuments.append(doc)
        activeDocumentID = doc.id
    }

    func closeActive() {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        stopFileWatcher(for: id)
        openDocuments.remove(at: idx)
        tabManager.remove(id)
        activeDocumentID = tabManager.activeID ?? openDocuments.last?.id
    }

    func cycleNextTab() {
        guard let current = activeDocumentID else { return }
        if let next = tabManager.nextMRU(after: current) {
            activeDocumentID = next
        }
    }

    func cyclePreviousTab() {
        guard let current = activeDocumentID else { return }
        if let prev = tabManager.previousMRU(before: current) {
            activeDocumentID = prev
        }
    }

    // MARK: - Save

    // MARK: - Active doc helpers

    var activeFileType: SupportedFileType? {
        guard let doc = activeDocument else { return nil }
        switch doc.kind {
        case .mindMap: return .mindMap
        case .text(_, let t): return t
        case .unsupported: return nil
        }
    }

    func insertSnippet(_ snippet: Snippet) {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        switch openDocuments[idx].kind {
        case .text(let body, let t):
            let glue = body.hasSuffix("\n") || body.isEmpty ? "" : "\n"
            openDocuments[idx].kind = .text(body + glue + snippet.body, fileType: t)
        case .mindMap(let map):
            let parent = map.root ?? Topic(text: "Root")
            if map.root == nil { map.root = parent }
            for line in snippet.body.split(whereSeparator: { $0 == "\n" }) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                _ = parent.addChild(text: trimmed)
            }
        case .unsupported:
            break
        }
    }

    // MARK: - AI

    func openAIGenerate() {
        guard let doc = activeDocument else { return }
        switch doc.kind {
        case .mindMap:
            aiSupportedModes = [.childTopic]
            aiDefaultPrompt = "Generate three child topics for the selected node."
        case .text(_, .markdown):
            aiSupportedModes = [.append, .replace]
            aiDefaultPrompt = "Continue the document below."
        case .text(_, .plantUML):
            aiSupportedModes = [.append, .replace]
            aiDefaultPrompt = "Generate a PlantUML diagram source for: "
        default:
            aiSupportedModes = [.append, .replace]
            aiDefaultPrompt = ""
        }
        aiGenerateOpen = true
    }

    func applyAIResult(text: String, mode: AIGeneratePane.InsertionMode) {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        var doc = openDocuments[idx]
        switch (doc.kind, mode) {
        case (.text(let body, let t), .append):
            doc.kind = .text(body + (body.hasSuffix("\n") ? "" : "\n") + text, fileType: t)
        case (.text(_, let t), .replace):
            doc.kind = .text(text, fileType: t)
        case (.mindMap(let map), .childTopic):
            // Split AI output by lines; each non-empty line becomes a child of the root.
            let parent = map.root ?? Topic(text: "Root")
            if map.root == nil { map.root = parent }
            for line in text.split(whereSeparator: { $0 == "\n" }) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                _ = parent.addChild(text: trimmed)
            }
        default:
            break
        }
        openDocuments[idx] = doc
    }

    func saveActive() {
        guard let doc = activeDocument else { return }
        if let url = doc.fileURL {
            do { try doc.save(to: url) }
            catch { lastError = "Save failed: \(error.localizedDescription)" }
        } else {
            saveActiveAs()
        }
    }

    func saveActiveAs() {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        let doc = openDocuments[idx]
        let panel = NSSavePanel()
        if let ext = doc.kind.preferredExtension {
            panel.allowedContentTypes = [UTType.init(filenameExtension: ext) ?? .data]
        }
        panel.nameFieldStringValue = doc.title.isEmpty ? L("picker.untitled_mindmap") : doc.title
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try doc.save(to: url)
                openDocuments[idx].fileURL = url
                openDocuments[idx].title = url.lastPathComponent
            } catch {
                lastError = String(format: L("error.save_failed"), error.localizedDescription)
            }
        }
    }
}

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
                    OutlinePanel(items: session.outlineItems) { _ in
                        // Click hook: future iterations will scroll the editor
                        // to `item.target`. For now the click is a no-op.
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

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var session: AppSession
    @Binding var selection: NodeData?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("sidebar.workspaces")).font(.headline)
                Spacer()
                Button { session.openWorkspace() } label: {
                    Image(systemName: "plus")
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if session.workspaceRoots.isEmpty {
                ContentUnavailableView(
                    L("sidebar.empty.title"),
                    systemImage: "folder",
                    description: Text(L("sidebar.empty.description"))
                )
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(session.workspaceRoots, id: \.self) { root in
                        Section {
                            NodeRow(node: root, selection: $selection)
                        } header: {
                            HStack {
                                Image(systemName: "folder.badge.gearshape")
                                Text(root.name).font(.headline)
                                Spacer()
                                Button {
                                    session.removeWorkspace(root)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .help(L("sidebar.tooltip.remove_workspace"))
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

struct NodeRow: View {
    let node: NodeData
    @Binding var selection: NodeData?

    var body: some View {
        if node.isExpandable {
            DisclosureGroup {
                ForEach(node.children(), id: \.self) { child in
                    NodeRow(node: child, selection: $selection)
                }
            } label: {
                HStack {
                    Image(systemName: node.isWorkspace ? "shippingbox" : "folder")
                    Text(node.name)
                }
                .tag(node)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: icon(for: node))
                    .foregroundStyle(.secondary)
                Text(node.name)
            }
            .tag(node)
        }
    }

    private func icon(for node: NodeData) -> String {
        switch node.fileType {
        case .mindMap: return "brain"
        case .markdown: return "text.alignleft"
        case .plantUML: return "rectangle.connected.to.line.below"
        case .csv: return "tablecells"
        case .plainText: return "doc.text"
        case .jpeg, .png: return "photo"
        case .none: return "doc"
        }
    }
}

// MARK: - Detail area (tabs + active editor)

struct DetailArea: View {
    @Binding var session: AppSession

    var body: some View {
        VStack(spacing: 0) {
            DocumentTabBar(session: $session)
                .frame(height: 32)
            Divider()
            if let doc = session.activeDocument {
                EditorPane(session: $session, documentID: doc.id, theme: session.theme.theme)
                    .id(doc.id)
            } else {
                ContentUnavailableView(
                    L("detail.empty.title"),
                    systemImage: "doc",
                    description: Text(L("detail.empty.description"))
                )
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct DocumentTabBar: View {
    @Binding var session: AppSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(session.openDocuments) { doc in
                    HStack(spacing: 4) {
                        Image(systemName: tabIcon(for: doc))
                        Text(doc.title)
                            .lineLimit(1)
                        if doc.hasExternalChanges {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                                .help(L("tab.tooltip.modified_externally"))
                        }
                        Button {
                            if let idx = session.openDocuments.firstIndex(where: { $0.id == doc.id }) {
                                session.openDocuments.remove(at: idx)
                                if session.activeDocumentID == doc.id {
                                    session.activeDocumentID = session.openDocuments.last?.id
                                }
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(doc.id == session.activeDocumentID ? Color.accentColor.opacity(0.18) : Color.clear)
                    )
                    .onTapGesture { session.activeDocumentID = doc.id }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func tabIcon(for doc: OpenDocument) -> String {
        switch doc.kind {
        case .mindMap: return "brain"
        case .text(_, .markdown): return "text.alignleft"
        case .text(_, .plantUML): return "rectangle.connected.to.line.below"
        case .text(_, .csv): return "tablecells"
        case .text: return "doc.text"
        case .unsupported: return "doc"
        }
    }
}

// MARK: - Editor router

struct EditorPane: View {
    @Binding var session: AppSession
    let documentID: OpenDocument.ID
    let theme: MindMapTheme
    @Environment(\.colorScheme) private var colorScheme

    private var documentIndex: Int? {
        session.openDocuments.firstIndex { $0.id == documentID }
    }

    var body: some View {
        if let idx = documentIndex {
            content(for: session.openDocuments[idx])
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func content(for document: OpenDocument) -> some View {
        switch document.kind {
        case .mindMap(let map):
            MindMapCanvas(
                map: map,
                theme: theme,
                onChange: { _ in /* dirty hook */ },
                onExtraFileTap: { url in session.open(url: url) }
            )
        case .text(_, .markdown):
            MarkdownEditor(
                text: textBinding(for: documentID),
                isDarkMode: colorScheme == .dark
            )
        case .text(_, .plantUML):
            PlantUMLEditor(
                text: textBinding(for: documentID),
                isDarkMode: colorScheme == .dark
            )
        case .text(_, .csv):
            CSVEditor(text: textBinding(for: documentID))
        case .text(let body, _):
            ScrollView {
                Text(body)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        case .unsupported(let path):
            VStack {
                Image(systemName: "doc.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                Text(L("plantuml.unsupported.unsupported_file_type"))
                Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func textBinding(for id: OpenDocument.ID) -> Binding<String> {
        Binding(
            get: {
                guard let idx = session.openDocuments.firstIndex(where: { $0.id == id }) else { return "" }
                if case .text(let s, _) = session.openDocuments[idx].kind { return s }
                return ""
            },
            set: { newValue in
                guard let idx = session.openDocuments.firstIndex(where: { $0.id == id }) else { return }
                if case .text(_, let t) = session.openDocuments[idx].kind {
                    session.openDocuments[idx].kind = .text(newValue, fileType: t)
                }
            }
        )
    }
}
