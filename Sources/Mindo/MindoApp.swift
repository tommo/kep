import SwiftUI
import MindoMindMap
import MindoModel
import UniformTypeIdentifiers

@main
struct MindoApp: App {
    @State private var document = MindoDocument()
    @State private var theme: ThemeChoice = .light
    @State private var lastError: String?

    var body: some Scene {
        WindowGroup("Mindo") {
            ContentView(document: $document, theme: $theme, lastError: $lastError)
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Mind Map") { document = MindoDocument.new() }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button("Open…") { openMindMap() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Save") { saveMindMap() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { saveAsMindMap() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                Picker("Theme", selection: $theme) {
                    Text("Light").tag(ThemeChoice.light)
                    Text("Dark").tag(ThemeChoice.dark)
                    Text("Classic").tag(ThemeChoice.classic)
                }
            }
        }
    }

    // MARK: - File operations

    private func openMindMap() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "mmd") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let map = try MindMap(text: text)
                document = MindoDocument(map: map, fileURL: url)
            } catch {
                lastError = "Open failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveMindMap() {
        if let url = document.fileURL {
            do {
                try document.map.write().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                lastError = "Save failed: \(error.localizedDescription)"
            }
        } else {
            saveAsMindMap()
        }
    }

    private func saveAsMindMap() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.init(filenameExtension: "mmd") ?? .data]
        panel.nameFieldStringValue = "Untitled.mmd"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try document.map.write().write(to: url, atomically: true, encoding: .utf8)
                document.fileURL = url
            } catch {
                lastError = "Save failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Document model

struct MindoDocument {
    var map: MindMap
    var fileURL: URL?

    init(map: MindMap = MindoDocument.bootstrap(), fileURL: URL? = nil) {
        self.map = map
        self.fileURL = fileURL
    }

    static func new() -> MindoDocument {
        return MindoDocument(map: bootstrap())
    }

    static func bootstrap() -> MindMap {
        let map = MindMap()
        let root = Topic(text: "Mind Map")
        map.root = root
        let intro = root.addChild(text: "Welcome to Mindo")
        _ = intro.addChild(text: "Press Tab to add a child")
        _ = intro.addChild(text: "Press Enter to add a sibling")
        _ = intro.addChild(text: "Double-click to edit")
        let features = root.addChild(text: "Features")
        _ = features.addChild(text: "Themes (Light / Dark / Classic)")
        _ = features.addChild(text: "Open .mmd files")
        return map
    }
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
    @Binding var document: MindoDocument
    @Binding var theme: ThemeChoice
    @Binding var lastError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let err = lastError {
                Text(err)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.15))
                    .onTapGesture { lastError = nil }
            }
            MindMapCanvas(map: document.map, theme: theme.theme) { _ in
                // Mutation hook — the canvas already mutates the model in-place.
            }
            .id(ObjectIdentifier(document.map)) // rebuild canvas when the map instance changes
        }
    }
}
