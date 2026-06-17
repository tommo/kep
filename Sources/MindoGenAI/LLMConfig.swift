import Foundation
import MindoCore

/// Persisted configuration for all LLM providers and the user's custom models.
/// Stored as `~/Library/Application Support/Mindo/llm_config.json`. Mirrors
/// `LlmConfig` from `mindolph-base`.
public struct LLMConfig: Codable, Sendable {
    /// Per-provider connection meta (API key + endpoint).
    public var providers: [String: ProviderMeta]
    /// User-defined models, keyed by provider ID.
    public var customModels: [String: [ModelMeta]]
    /// Active provider/model selection — what the AI panes default to.
    public var activeProviderID: String?
    public var activeModel: String?

    public init(
        providers: [String: ProviderMeta] = [:],
        customModels: [String: [ModelMeta]] = [:],
        activeProviderID: String? = nil,
        activeModel: String? = nil
    ) {
        self.providers = providers
        self.customModels = customModels
        self.activeProviderID = activeProviderID
        self.activeModel = activeModel
    }
}

/// Provides a deterministic catalogue of built-in models per provider so the
/// user has something to pick before adding their own.
public enum BuiltInModels {
    public static func models(for provider: GenAIProviderID) -> [ModelMeta] {
        switch provider {
        case .openAI:
            return [
                ModelMeta(name: "gpt-4o", maxTokens: 16384),
                ModelMeta(name: "gpt-4o-mini", maxTokens: 16384),
                ModelMeta(name: "gpt-4.1", maxTokens: 32768),
                ModelMeta(name: "o1-mini", maxTokens: 65536),
            ]
        case .ollama:
            return [
                ModelMeta(name: "llama3.1", maxTokens: 8192),
                ModelMeta(name: "qwen2.5", maxTokens: 8192),
                ModelMeta(name: "mistral", maxTokens: 8192),
            ]
        case .deepSeek:
            // Current V4 line only (the old deepseek-chat / deepseek-reasoner
            // names are deprecated). flash is the default; both are reasoning
            // models — the dialog uses the non-streaming completion so their
            // replies render correctly.
            return [
                ModelMeta(name: "deepseek-v4-flash", maxTokens: 8192),
                ModelMeta(name: "deepseek-v4-pro", maxTokens: 8192),
            ]
        case .moonshot:
            return [
                ModelMeta(name: "moonshot-v1-8k", maxTokens: 8192),
                ModelMeta(name: "moonshot-v1-32k", maxTokens: 32768),
                ModelMeta(name: "moonshot-v1-128k", maxTokens: 131072),
            ]
        case .qwen:
            return [
                ModelMeta(name: "qwen-plus", maxTokens: 32768),
                ModelMeta(name: "qwen-max", maxTokens: 32768),
                ModelMeta(name: "qwen-turbo", maxTokens: 8192),
            ]
        case .gemini:
            return [
                ModelMeta(name: "gemini-2.5-pro", maxTokens: 65536),
                ModelMeta(name: "gemini-2.5-flash", maxTokens: 65536),
            ]
        case .huggingFace, .chatGLM:
            return []
        }
    }
}

/// Loads/saves `LLMConfig`, plus convenience model lookup combining built-in +
/// custom models. Singleton matching the Java `LlmConfig`.
public final class LLMConfigStore {
    public static let shared = LLMConfigStore()

    public private(set) var config: LLMConfig
    private let url: URL

    public init(directory: URL = LLMConfigStore.defaultDirectory) {
        self.url = directory.appendingPathComponent("llm_config.json")
        self.config = JSONFile.read(LLMConfig.self, from: url) ?? LLMConfig()
    }

    public static var defaultDirectory: URL {
        MindoCore.applicationSupportURL
    }

    public func save() throws {
        try JSONFile.write(config, to: url)
    }

    public func setProviderMeta(_ meta: ProviderMeta, for providerID: GenAIProviderID) {
        config.providers[providerID.rawValue] = meta
        try? save()
    }

    public func providerMeta(for providerID: GenAIProviderID) -> ProviderMeta {
        var meta = config.providers[providerID.rawValue] ?? ProviderMeta()
        // Fall back to the provider's env var when no key is configured.
        if meta.apiKey.isEmpty, let env = providerID.apiKeyEnvVar,
           let key = ProcessInfo.processInfo.environment[env], !key.isEmpty {
            meta.apiKey = key
        }
        if meta.endpoint.isEmpty { meta.endpoint = providerID.defaultEndpoint }
        return meta
    }

    /// Whether `providerID` has a usable API key (configured or from the
    /// environment). Ollama needs none.
    public func hasUsableKey(for providerID: GenAIProviderID) -> Bool {
        if providerID == .ollama { return true }
        return !providerMeta(for: providerID).apiKey.isEmpty
    }

    /// All known models for a provider — built-ins first, then user's customs.
    public func allModels(for providerID: GenAIProviderID) -> [ModelMeta] {
        let builtin = BuiltInModels.models(for: providerID)
        let custom = config.customModels[providerID.rawValue] ?? []
        return builtin + custom
    }

    /// Look up a model's full meta by name, falling back to a name-only stub
    /// when the user supplied a model that isn't in our built-in/custom lists.
    public func modelMeta(for providerID: GenAIProviderID, name: String) -> ModelMeta {
        allModels(for: providerID).first(where: { $0.name == name }) ?? ModelMeta(name: name)
    }

    public func addCustomModel(_ model: ModelMeta, for providerID: GenAIProviderID) {
        var list = config.customModels[providerID.rawValue] ?? []
        list.removeAll { $0.name == model.name }
        list.append(model)
        config.customModels[providerID.rawValue] = list
        try? save()
    }

    /// Update the user's currently active provider+model selection. Persists.
    public func setActive(provider: GenAIProviderID, model: String) {
        config.activeProviderID = provider.rawValue
        config.activeModel = model
        try? save()
    }

    /// `(provider, model)` — falls back to first available if nothing set.
    public func activeSelection() -> (GenAIProviderID, String)? {
        if let raw = config.activeProviderID,
           let provider = GenAIProviderID(rawValue: raw),
           let model = config.activeModel,
           !model.isEmpty {
            return (provider, model)
        }
        // No explicit selection — prefer a provider that actually has a usable
        // key (configured or from the environment), so an env-only setup just
        // works instead of defaulting to a keyless provider.
        for id in GenAIProviderID.allCases where !providerMeta(for: id).apiKey.isEmpty {
            if let first = allModels(for: id).first { return (id, first.name) }
        }
        for id in GenAIProviderID.allCases {
            if let first = allModels(for: id).first { return (id, first.name) }
        }
        return nil
    }
}
