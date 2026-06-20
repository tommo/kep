import SwiftUI
import Combine

/// Modal sheet that lets the user enter a prompt, watch the response stream in,
/// and insert it into the calling editor. The host passes a closure that knows
/// how to apply accepted text to the document.
public struct AIGeneratePane: View {
    public enum InsertionMode: String, CaseIterable, Hashable, Sendable {
        case append    = "Append"
        case replace   = "Replace selection"
        case childTopic = "As child topic"
    }

    public struct Context: Sendable {
        public var selectedText: String
        public var supportedModes: [InsertionMode]
        public var defaultPrompt: String
        public init(selectedText: String = "", supportedModes: [InsertionMode] = [.append, .replace], defaultPrompt: String = "") {
            self.selectedText = selectedText
            self.supportedModes = supportedModes
            self.defaultPrompt = defaultPrompt
        }
    }

    @Environment(\.dismiss) private var dismiss

    public let title: String
    public let context: Context
    public let onAccept: (String, InsertionMode) -> Void

    @State private var prompt: String
    @State private var insertionMode: InsertionMode
    @State private var output: String = ""
    @State private var isRunning: Bool = false
    @State private var errorMessage: String?
    @State private var providerLabel: String = ""
    @State private var subscriptions: Set<AnyCancellable> = []
    /// Snapshot of the prompt that produced `output`. Regenerate replays this
    /// (not the live `prompt` text, which the user may have edited since).
    @State private var lastPromptUsed: String?
    /// Active provider — fixed for the life of the sheet (changing providers
    /// is a Settings concern, not a per-prompt one).
    @State private var activeProvider: GenAIProviderID?
    /// Per-request model override. Persists via LLMConfigStore.setActive on
    /// change, so the choice carries over to the next sheet open and to
    /// other call sites that read activeSelection().
    @State private var selectedModel: String = ""
    @State private var availableModels: [String] = []
    /// Sampling temperature preset (javamind parity). Sent to the provider.
    @State private var temperature: AITemperature = .default
    /// Output-language id ("" = Auto). Non-Auto appends a directive to the prompt.
    @State private var languageID: String = AIOutputLanguage.auto.id
    @FocusState private var promptFocused: Bool

    public init(
        title: String = "AI Generate",
        context: Context,
        onAccept: @escaping (String, InsertionMode) -> Void
    ) {
        self.title = title
        self.context = context
        self.onAccept = onAccept
        _prompt = State(initialValue: context.defaultPrompt)
        _insertionMode = State(initialValue: context.supportedModes.first ?? .append)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            promptSection
            Divider()
            outputSection
            Divider()
            footer
        }
        .frame(width: 600, height: 540)
        .onAppear {
            refreshActiveProviderLabel()
            // Focus the prompt editor on appear so the user can start
            // typing without clicking. Tiny delay sidesteps SwiftUI's
            // initial-focus race during sheet present.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                promptFocused = true
            }
        }
        .onDisappear { cancel() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            Text(title).font(.title3).bold()
            Spacer()
            if !providerLabel.isEmpty {
                Text(providerLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if availableModels.count > 1 {
                Picker("", selection: $selectedModel) {
                    ForEach(availableModels, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                .disabled(isRunning)
                .onChange(of: selectedModel) { _, new in
                    guard let provider = activeProvider, !new.isEmpty else { return }
                    LLMConfigStore.shared.setActive(provider: provider, model: new)
                }
            } else if !selectedModel.isEmpty {
                Text(selectedModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Close") { cancel(); dismiss() }
        }
        .padding()
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Prompt").font(.headline)
                Spacer()
                if context.supportedModes.count > 1 {
                    Picker("", selection: $insertionMode) {
                        ForEach(context.supportedModes, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
            }
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 80)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .focused($promptFocused)
            optionsRow
            if !context.selectedText.isEmpty {
                Text("Context (selected): \(context.selectedText.prefix(160))…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    /// Per-request generation controls — temperature preset + output language.
    private var optionsRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.medium").foregroundStyle(.secondary)
                Picker("Temperature", selection: $temperature) {
                    ForEach(AITemperature.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)
            }
            .help("Sampling temperature — lower is more deterministic, higher more creative")

            HStack(spacing: 6) {
                Image(systemName: "globe").foregroundStyle(.secondary)
                Picker("Language", selection: $languageID) {
                    ForEach(AIOutputLanguage.all) { lang in
                        Text(lang.name).tag(lang.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }
            .help("Ask the model to respond in a specific language")

            Spacer()
        }
        .disabled(isRunning)
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Result").font(.headline)
                if isRunning {
                    ProgressView().controlSize(.small).padding(.leading, 6)
                }
                Spacer()
                if let err = errorMessage {
                    Text(err).foregroundStyle(.red).font(.caption).lineLimit(1)
                }
            }
            ScrollView {
                Text(output.isEmpty ? "—" : output)
                    .font(.system(.body, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button("Generate", systemImage: "play.fill") { startGenerate() }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(isRunning || prompt.isEmpty)
            Button("Regenerate", systemImage: "arrow.clockwise") { regenerate() }
                .disabled(isRunning || lastPromptUsed == nil)
                .help("Re-run the prompt that produced the current result")
            Button("Continue", systemImage: "arrow.right.to.line") { continueResponse() }
                .disabled(isRunning || output.isEmpty)
                .help("Ask the model to continue from the current result")
            if isRunning {
                Button("Stop") { cancel() }
            }
            Spacer()
            Button("Discard") { dismiss() }
                .keyboardShortcut(.cancelAction) // Esc
            Button("Insert") {
                onAccept(output, insertionMode)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(output.isEmpty || isRunning)
        }
        .padding()
    }

    // MARK: - Actions

    private func refreshActiveProviderLabel() {
        if let (provider, model) = LLMConfigStore.shared.activeSelection() {
            activeProvider = provider
            availableModels = LLMConfigStore.shared.allModels(for: provider).map { $0.name }
            // Make sure the active model is in the list — if it isn't (custom
            // model that was deleted), stash it at the front so the picker
            // still shows it and the user notices.
            if !availableModels.contains(model) { availableModels.insert(model, at: 0) }
            selectedModel = model
            providerLabel = provider.displayName
        } else {
            activeProvider = nil
            availableModels = []
            selectedModel = ""
            providerLabel = "No provider configured"
        }
    }

    private func startGenerate() {
        run(promptText: prompt, appendingToExisting: false, rememberAs: prompt)
    }

    private func regenerate() {
        guard let last = lastPromptUsed else { return }
        run(promptText: last, appendingToExisting: false, rememberAs: last)
    }

    private func continueResponse() {
        guard !output.isEmpty else { return }
        run(
            promptText: Self.continuationPrompt(from: output),
            appendingToExisting: true,
            rememberAs: lastPromptUsed
        )
    }

    /// Shared runner for Generate / Regenerate / Continue. `appendingToExisting`
    /// preserves the current `output` (Continue mode); otherwise the buffer is
    /// reset before streaming. `rememberAs` is what Regenerate will replay later
    /// — pass `nil` to leave the previous value in place (used by Continue, which
    /// shouldn't change what Regenerate replays).
    private func run(promptText: String, appendingToExisting: Bool, rememberAs: String?) {
        guard let provider = activeProvider, !selectedModel.isEmpty else {
            errorMessage = "Configure a provider in Settings first."
            return
        }
        let modelMeta = LLMConfigStore.shared.modelMeta(for: provider, name: selectedModel)
        let language = AIOutputLanguage.by(id: languageID)
        let withContext = context.selectedText.isEmpty
            ? promptText
            : "\(promptText)\n\nContext:\n\(context.selectedText)"
        // Providers don't read LLMInput.outputLanguage, so the directive must
        // live in the prompt; we still set the field for downstream/telemetry.
        let combined = language.applied(to: withContext)
        let input = LLMInput(
            providerID: provider.rawValue,
            model: modelMeta.name,
            text: combined,
            temperature: temperature.value,
            maxTokens: modelMeta.maxTokens,
            outputLanguage: language.isAuto ? nil : language.id,
            isStreaming: true
        )

        if !appendingToExisting { output = "" }
        if let remember = rememberAs { lastPromptUsed = remember }
        errorMessage = nil
        isRunning = true
        subscriptions.removeAll()
        let service = LLMService.shared
        service.partials
            .receive(on: RunLoop.main)
            .sink { partial in
                if !partial.text.isEmpty { output.append(partial.text) }
                if partial.isStop { isRunning = false }
            }
            .store(in: &subscriptions)
        service.errors
            .receive(on: RunLoop.main)
            .sink { err in
                errorMessage = err.errorDescription
                isRunning = false
            }
            .store(in: &subscriptions)
        service.stream(input: input)
    }

    /// Builds the prompt sent for "Continue" — the model sees its own prior
    /// reply and is asked to extend it without repeating. Exposed for tests.
    public static func continuationPrompt(from existing: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Continue the following text from exactly where it stops. Do not repeat any of it; emit only the continuation.

        \(trimmed)
        """
    }

    private func cancel() {
        LLMService.shared.cancel()
        isRunning = false
        subscriptions.removeAll()
    }
}
