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

    /// When true and `agentReply` is set, sends run the tool-calling agent loop
    /// (the model can call `kep` tools) instead of plain completion. On by
    /// default so the assistant can fetch documents / act out of the box.
    @Published public var agentMode: Bool = true
    /// App-provided agent runner: given the conversation, returns the final
    /// reply after any tool calls. Nil → no agent available (toggle hidden).
    public var agentReply: (([ChatMessage]) async throws -> String)?
    public var hasAgent: Bool { agentReply != nil }

    private var subscriptions: Set<AnyCancellable> = []
    private let service: LLMService

    public init(systemPrompt: String = Conversation.defaultSystemPrompt,
                contextBlock: String? = nil,
                service: LLMService = .shared,
                agentReply: (([ChatMessage]) async throws -> String)? = nil) {
        self.conversation = Conversation(systemPrompt: systemPrompt, contextBlock: contextBlock)
        self.service = service
        self.agentReply = agentReply
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

        // Agent mode: run the tool-calling loop (non-streaming) and append the
        // final reply. The agent may call kep tools that edit the doc.
        if agentMode, let agentReply {
            let messages = conversation.llmMessages()
            Task { @MainActor in
                do {
                    let reply = try await agentReply(messages)
                    self.conversation.addAssistant(reply)
                } catch {
                    self.errorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                }
                self.isRunning = false
            }
            return
        }

        let meta = LLMConfigStore.shared.modelMeta(for: provider, name: model)
        let input = LLMInput(
            providerID: provider.rawValue,
            model: model,
            text: text,
            messages: conversation.llmMessages(),
            maxTokens: meta.maxTokens,
            isStreaming: false
        )

        // Non-streaming completion — robust for reasoning models (deepseek-v4-flash
        // streams only reasoning_content frames, which the SSE path mishandled).
        Task { @MainActor in
            do {
                let (reply, _) = try await self.service.complete(input)
                if reply.isEmpty {
                    self.errorText = "The model returned an empty response."
                } else {
                    self.conversation.addAssistant(reply)
                }
            } catch {
                self.errorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            self.isRunning = false
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
