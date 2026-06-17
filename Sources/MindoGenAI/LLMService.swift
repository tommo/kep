import Foundation
import Combine

/// Single entry-point that wraps `LLMProviderFactory` + `LLMConfigStore` and
/// publishes Combine events for UI binding. Mirrors `LlmService` + the
/// `GenAiEvents` event bus from the Java codebase.
public final class LLMService {
    public static let shared = LLMService()

    private var cache: [GenAIProviderID: LLMProvider] = [:]
    private let queue = DispatchQueue(label: "mindo.genai.service")
    private(set) var currentProvider: LLMProvider?

    public let partials = PassthroughSubject<StreamPartial, Never>()
    public let errors = PassthroughSubject<LLMError, Never>()

    public init() {}

    public func provider(for providerID: GenAIProviderID, model: ModelMeta) -> LLMProvider? {
        return queue.sync {
            // Always re-read the meta so a key/endpoint configured AFTER a
            // provider was first created takes effect (the cached provider would
            // otherwise keep an empty/stale API key).
            let meta = LLMConfigStore.shared.providerMeta(for: providerID)
            if let existing = cache[providerID] as? OpenAICompatibleProvider,
               existing.model.name == model.name {
                existing.meta = meta
                return existing
            }
            guard let p = LLMProviderFactory.create(providerID: providerID, meta: meta, model: model) else {
                return nil
            }
            cache[providerID] = p
            return p
        }
    }

    /// Non-streaming completion (text + any tool calls). More robust than the
    /// SSE stream for reasoning models (deepseek-v4-flash etc.), which is why
    /// the dialog uses it.
    public func complete(_ input: LLMInput) async throws -> (text: String, toolCalls: [ToolCall]) {
        guard let providerID = GenAIProviderID(rawValue: input.providerID) else {
            throw LLMError.transport("Unknown provider \(input.providerID)")
        }
        let modelMeta = LLMConfigStore.shared.modelMeta(for: providerID, name: input.model)
        guard let provider = provider(for: providerID, model: modelMeta) as? OpenAICompatibleProvider else {
            throw LLMError.transport("Provider \(providerID.displayName) is not available")
        }
        return try await provider.complete(input)
    }

    public func cancel() {
        currentProvider?.cancel()
        currentProvider = nil
    }

    /// Fire-and-forget streaming entry point — emits each partial on `partials`.
    @discardableResult
    public func stream(input: LLMInput) -> Task<Void, Never> {
        return Task { [weak self] in
            guard let self else { return }
            guard let providerID = GenAIProviderID(rawValue: input.providerID) else {
                self.errors.send(.transport("Unknown provider \(input.providerID)"))
                return
            }
            let modelMeta = LLMConfigStore.shared.modelMeta(for: providerID, name: input.model)
            guard let provider = self.provider(for: providerID, model: modelMeta) else {
                self.errors.send(.transport("Provider \(providerID.displayName) is not yet implemented"))
                return
            }
            self.currentProvider = provider
            do {
                try await provider.stream(input) { partial in
                    self.partials.send(partial)
                }
            } catch let err as LLMError {
                self.errors.send(err)
            } catch {
                self.errors.send(.transport(error.localizedDescription))
            }
            self.currentProvider = nil
        }
    }
}
