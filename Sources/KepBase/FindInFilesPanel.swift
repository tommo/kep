import SwiftUI
import KepCore

/// SwiftUI panel that runs `SearchService` against a list of workspace roots
/// and surfaces `FoundFile` results. Click a hit → callback opens the file
/// (the App is in charge of routing).
@MainActor
public struct FindInFilesPanel: View {
    public let workspaceRoots: [URL]
    public let onOpen: (URL, SearchHit) -> Void

    @State private var query: String = ""
    @State private var caseSensitive: Bool = false
    @State private var wholeWord: Bool = false
    @State private var regex: Bool = false
    @State private var results: [FoundFile] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @State private var debouncer = Debouncer()

    public init(workspaceRoots: [URL], onOpen: @escaping (URL, SearchHit) -> Void) {
        self.workspaceRoots = workspaceRoots
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find in workspace files…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: query) { _, _ in scheduleSearch() }
                Toggle("Aa", isOn: $caseSensitive)
                    .toggleStyle(.button)
                    .help("Case-sensitive search")
                    .onChange(of: caseSensitive) { _, _ in scheduleSearch() }
                Toggle("W", isOn: $wholeWord)
                    .toggleStyle(.button)
                    .help("Match whole words only")
                    .disabled(regex)
                    .onChange(of: wholeWord) { _, _ in scheduleSearch() }
                Toggle(".*", isOn: $regex)
                    .toggleStyle(.button)
                    .help("Treat the query as a regular expression")
                    .onChange(of: regex) { _, _ in scheduleSearch() }
                if isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(8)
            Divider()

            if workspaceRoots.isEmpty {
                ContentUnavailableView(
                    "No Workspaces",
                    systemImage: "folder",
                    description: Text("Add a workspace from the sidebar to search.")
                ).frame(maxHeight: .infinity)
            } else if query.isEmpty {
                ContentUnavailableView(
                    "Type to Search",
                    systemImage: "magnifyingglass",
                    description: Text("Searches every text file under your workspaces.")
                ).frame(maxHeight: .infinity)
            } else if results.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "questionmark.circle",
                    description: Text("Nothing found for \"\(query)\".")
                ).frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(results) { file in
                        Section {
                            ForEach(file.hits, id: \.self) { hit in
                                Button {
                                    onOpen(file.url, hit)
                                } label: {
                                    HStack(alignment: .top) {
                                        Text("\(hit.lineNumber)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32, alignment: .trailing)
                                        Text(Self.highlighted(hit))
                                            .lineLimit(2)
                                            .truncationMode(.tail)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            // Workspace-relative path, so same-named files in
                            // different folders are distinguishable.
                            Label(relativeLabel(for: file.url), systemImage: "doc.text")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onDisappear { searchTask?.cancel(); debouncer.cancel() }
    }

    /// Path shown in a result section header — relative to the owning
    /// workspace (so "Notes/a.md" vs "Archive/a.md" are distinguishable),
    /// falling back to the bare filename.
    private func relativeLabel(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        for root in workspaceRoots {
            let base = root.deletingLastPathComponent().standardizedFileURL.path
            if path.hasPrefix(base + "/") { return String(path.dropFirst(base.count + 1)) }
        }
        return url.lastPathComponent
    }

    /// The matched line with the matched substring emphasised, so it's obvious
    /// what matched within the line.
    private static func highlighted(_ hit: SearchHit) -> AttributedString {
        var attr = AttributedString(hit.line)
        if let strRange = Range(hit.matchRange, in: hit.line),
           let attrRange = Range(strRange, in: attr) {
            attr[attrRange].inlinePresentationIntent = .stronglyEmphasized
            attr[attrRange].foregroundColor = .accentColor
        }
        return attr
    }

    private func scheduleSearch() {
        debouncer.schedule(after: 0.25) { Task { @MainActor in runSearch() } }
    }

    private func runSearch() {
        searchTask?.cancel()
        let q = query
        let opts = SearchOptions(caseSensitive: caseSensitive, regex: regex, wholeWord: wholeWord)
        guard !q.isEmpty else { results = []; return }
        isSearching = true
        let roots = workspaceRoots
        searchTask = Task.detached {
            let svc = SearchService()
            var combined: [FoundFile] = []
            for root in roots {
                if Task.isCancelled { return }
                combined.append(contentsOf: svc.search(in: root, query: q, options: opts))
            }
            let found = combined   // immutable hand-off into the main-actor closure
            await MainActor.run {
                self.results = found
                self.isSearching = false
            }
        }
    }
}
