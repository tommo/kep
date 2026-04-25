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
    @State private var results: [FoundFile] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @State private var debounce: DispatchWorkItem?

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
        .onDisappear { searchTask?.cancel(); debounce?.cancel() }
    }

    private func scheduleSearch() {
        debounce?.cancel()
        let work = DispatchWorkItem { runSearch() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func runSearch() {
        searchTask?.cancel()
        let q = query
        let cs = caseSensitive
        guard !q.isEmpty else { results = []; return }
        isSearching = true
        let roots = workspaceRoots
        searchTask = Task.detached {
            let svc = SearchService()
            var combined: [FoundFile] = []
            for root in roots {
                if Task.isCancelled { return }
                combined.append(contentsOf: svc.search(in: root, query: q, options: SearchOptions(caseSensitive: cs)))
            }
            await MainActor.run {
                self.results = combined
                self.isSearching = false
            }
        }
    }
}
