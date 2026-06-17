import Foundation
import Combine

/// Drives a multi-turn `Conversation` against `LLMService`. Owns the streaming
/// subscription and exposes published state for `DialogView`. The pure
/// turn/wire logic lives in `Conversation`; this is the thin networking glue,
/// mirroring `AIGeneratePane.run`.
@MainActor
public final class ConversationViewModel: ObservableObject {
    @Published public var conversation: Conversation
    @Published public var draft: String = ""
    @Published public var isRunning: Bool = false
    @Published public var errorText: String?
    @Published public private(set) var providerLabel: String = ""
    /// Models offered for the active provider (built-in + custom).
    @Published public var availableModels: [String] = []
    /// Selected model — persisted as the active selection so it carries across
    /// the app. Drives the model picker in the dialog header.
    @Published public var selectedModel: String = "" {
        didSet {
            guard selectedModel != oldValue, let p = activeProvider, !selectedModel.isEmpty else { return }
            LLMConfigStore.shared.setActive(provider: p, model: selectedModel)
        }
    }
    private var activeProvider: GenAIProviderID?

    private var subscriptions: Set<AnyCancellable> = []
    private let service: LLMService

    public init(systemPrompt: String = Conversation.defaultSystemPrompt,
                contextBlock: String? = nil,
                service: LLMService = .shared) {
        self.conversation = Conversation(systemPrompt: systemPrompt, contextBlock: contextBlock)
        self.service = service
        refreshProviderLabel()
    }

    /// Replace the per-send context (active doc / selection / links). Cheap to
    /// call right before `send` so the model always sees current state.
    public func setContext(_ block: String?) { conversation.contextBlock = block }

    public func refreshProviderLabel() {
        if let (provider, model) = LLMConfigStore.shared.activeSelection() {
            activeProvider = provider
            providerLabel = provider.displayName
            var models = LLMConfigStore.shared.allModels(for: provider).map(\.name)
            if !models.contains(model) { models.insert(model, at: 0) }
            availableModels = models
            if selectedModel != model { selectedModel = model }
        } else {
            activeProvider = nil
            providerLabel = "No provider configured"
            availableModels = []
            selectedModel = ""
        }
    }

    public var canSend: Bool {
        !isRunning && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        guard let provider = activeProvider, !selectedModel.isEmpty else {
            errorText = "Configure a provider in Settings first."
            return
        }
        let model = selectedModel
        conversation.addUser(text)
        draft = ""
        errorText = nil
        isRunning = true

        let meta = LLMConfigStore.shared.modelMeta(for: provider, name: model)
        let input = LLMInput(
            providerID: provider.rawValue,
            model: model,
            text: text,
            messages: conversation.llmMessages(),
            maxTokens: meta.maxTokens,
            isStreaming: true
        )
        Self.diag("SEND provider=\(provider.rawValue) model=\(model) keySet=\(!LLMConfigStore.shared.providerMeta(for: provider).apiKey.isEmpty) msgs=\(input.wireMessages.count)")

        subscriptions.removeAll()
        service.partials
            .receive(on: RunLoop.main)
            .sink { [weak self] partial in
                guard let self else { return }
                Self.diag("PARTIAL len=\(partial.text.count) stop=\(partial.isStop)")
                if !partial.text.isEmpty { self.conversation.appendToLastAssistant(partial.text) }
                if partial.isStop { self.isRunning = false }
            }
            .store(in: &subscriptions)
        service.errors
            .receive(on: RunLoop.main)
            .sink { [weak self] err in
                guard let self else { return }
                Self.diag("ERROR \(err.errorDescription ?? "?")")
                self.errorText = err.errorDescription
                self.isRunning = false
            }
            .store(in: &subscriptions)
        service.stream(input: input)
    }

    /// Temporary file diagnostics for the "no response" report — /tmp/mindo-ai.log.
    static func diag(_ s: String) {
        let url = URL(fileURLWithPath: "/tmp/mindo-ai.log")
        let line = s + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            h.seekToEndOfFile(); h.write(Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    public func cancel() {
        service.cancel()
        isRunning = false
        subscriptions.removeAll()
    }

    public func clear() {
        cancel()
        conversation.clear()
        errorText = nil
    }

    /// The most recent assistant reply, for an "Insert into document" action.
    public var lastAssistantText: String? {
        conversation.turns.last(where: { $0.role == .assistant && !$0.content.isEmpty })?.content
    }
}
