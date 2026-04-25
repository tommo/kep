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
            if let existing = cache[providerID], existing.model.name == model.name {
                return existing
            }
            let meta = LLMConfigStore.shared.providerMeta(for: providerID)
            guard let p = LLMProviderFactory.create(providerID: providerID, meta: meta, model: model) else {
                return nil
            }
            cache[providerID] = p
            return p
        }
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
