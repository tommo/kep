import SwiftUI
import MindoCore

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
                        Section(file.url.lastPathComponent) {
                            ForEach(file.hits, id: \.self) { hit in
                                Button {
                                    onOpen(file.url, hit)
                                } label: {
                                    HStack(alignment: .top) {
                                        Text("\(hit.lineNumber)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 32, alignment: .trailing)
                                        Text(hit.line.trimmingCharacters(in: .whitespaces))
                                            .lineLimit(2)
                                            .truncationMode(.tail)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onDisappear { searchTask?.cancel(); debouncer.cancel() }
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
            await MainActor.run {
                self.results = combined
                self.isSearching = false
            }
        }
    }
}
