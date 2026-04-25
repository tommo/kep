import Foundation

/// Concrete OpenAI-compatible providers. Each tweaks defaults but inherits the
/// shared chat-completions wire format from `OpenAICompatibleProvider`.
public final class OpenAIProvider: OpenAICompatibleProvider, @unchecked Sendable {
    public init(meta: ProviderMeta, model: ModelMeta) {
        super.init(providerID: .openAI, meta: meta, model: model)
    }
}

public final class OllamaProvider: OpenAICompatibleProvider, @unchecked Sendable {
    public init(meta: ProviderMeta, model: ModelMeta) {
        var m = meta
        if m.endpoint.isEmpty { m.endpoint = GenAIProviderID.ollama.defaultEndpoint }
        super.init(providerID: .ollama, meta: m, model: model)
    }

    /// Ollama doesn't require an API key — override so we don't send a bogus header.
    public override func makeRequest(_ input: LLMInput, streaming: Bool) throws -> URLRequest {
        var req = try super.makeRequest(input, streaming: streaming)
        req.setValue(nil, forHTTPHeaderField: "Authorization")
        return req
    }
}

public final class DeepSeekProvider: OpenAICompatibleProvider, @unchecked Sendable {
    public init(meta: ProviderMeta, model: ModelMeta) {
        super.init(providerID: .deepSeek, meta: meta, model: model)
    }
}

public final class MoonshotProvider: OpenAICompatibleProvider, @unchecked Sendable {
    public init(meta: ProviderMeta, model: ModelMeta) {
        super.init(providerID: .moonshot, meta: meta, model: model)
    }
}

public final class QwenProvider: OpenAICompatibleProvider, @unchecked Sendable {
    public init(meta: ProviderMeta, model: ModelMeta) {
        super.init(providerID: .qwen, meta: meta, model: model)
    }
}

/// Factory that turns a `(GenAIProviderID, ProviderMeta, ModelMeta)` tuple into
/// a concrete `LLMProvider`. Mirrors `LlmProviderFactory`.
public enum LLMProviderFactory {
    public static func create(providerID: GenAIProviderID, meta: ProviderMeta, model: ModelMeta) -> LLMProvider? {
        switch providerID {
        case .openAI:    return OpenAIProvider(meta: meta, model: model)
        case .ollama:    return OllamaProvider(meta: meta, model: model)
        case .deepSeek:  return DeepSeekProvider(meta: meta, model: model)
        case .moonshot:  return MoonshotProvider(meta: meta, model: model)
        case .qwen:      return QwenProvider(meta: meta, model: model)
        case .gemini:    return GeminiProvider(meta: meta, model: model)
        // HuggingFace and ChatGLM still use distinct shapes that don't map to
        // either OpenAI-compat or Gemini's contents/parts envelope. Keep
        // honest about that until they're wired.
        case .huggingFace, .chatGLM:
            return nil
        }
    }
}
