import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MindoCore
import MindoMindMap
import MindoCSV
import MindoGenAI
import MindoMarkdown
import MindoPlantUML
import MindoModel

@main
struct MindoApp: App {
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
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Mind Map") { session.newMindMap() }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button("Open Workspace…") { session.openWorkspace() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Open File…") { session.openFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Save") { session.saveActive() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { session.saveActiveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Close Tab") { session.closeActive() }
                    .keyboardShortcut("w", modifiers: .command)
                    .disabled(session.activeDocument == nil)
            }
            CommandMenu("View") {
                Picker("Theme", selection: $session.theme) {
                    Text("Light").tag(ThemeChoice.light)
                    Text("Dark").tag(ThemeChoice.dark)
                    Text("Classic").tag(ThemeChoice.classic)
                }
            }
            CommandMenu("AI") {
                Button("Generate…") { session.openAIGenerate() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(session.activeDocument == nil)
                Divider()
                Button("Settings…") { session.aiSettingsOpen = true }
                    .keyboardShortcut(",", modifiers: [.command, .shift])
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
    var activeDocumentID: OpenDocument.ID?
    var theme: ThemeChoice = .light
    var lastError: String?

    // AI sheets
    var aiSettingsOpen: Bool = false
    var aiGenerateOpen: Bool = false
    var aiSupportedModes: [AIGeneratePane.InsertionMode] = [.append]
    var aiDefaultPrompt: String = ""

    init() {
        let mgr = WorkspaceManager.shared
        mgr.removeNonExistentWorkspaces()
        self.workspaces = mgr.list.projects
        self.workspaceRoots = workspaces.map { mgr.loadTree(for: $0) }
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
            workspaceRoots.append(mgr.loadTree(for: meta))
        }
    }

    func removeWorkspace(_ root: NodeData) {
        let mgr = WorkspaceManager.shared
        let meta = WorkspaceMeta(url: root.url)
        mgr.remove(meta)
        workspaces = mgr.list.projects
        workspaceRoots.removeAll { $0.url == root.url }
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
        } catch {
            lastError = "Open failed: \(error.localizedDescription)"
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
        openDocuments.remove(at: idx)
        activeDocumentID = openDocuments.last?.id
    }

    // MARK: - Save

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
        panel.nameFieldStringValue = doc.title
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try doc.save(to: url)
                openDocuments[idx].fileURL = url
                openDocuments[idx].title = url.lastPathComponent
            } catch {
                lastError = "Save failed: \(error.localizedDescription)"
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
        }
        .onChange(of: sidebarSelection) { _, new in
            if let node = new, node.isFile {
                session.open(url: node.url)
            }
        }
        .alert("Mindo", isPresented: Binding(
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
                Text("Workspaces").font(.headline)
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
                    "No Workspaces",
                    systemImage: "folder",
                    description: Text("Click + to add a folder.")
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
                                .help("Remove workspace from list")
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
                    "No Document Open",
                    systemImage: "doc",
                    description: Text("Open a workspace, then click a file in the sidebar.")
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
            MindMapCanvas(map: map, theme: theme) { _ in /* dirty hook */ }
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
                Text("Unsupported file type")
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
