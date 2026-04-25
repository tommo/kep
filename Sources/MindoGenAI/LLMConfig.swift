import Foundation

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
            return [
                ModelMeta(name: "deepseek-chat", maxTokens: 8192),
                ModelMeta(name: "deepseek-reasoner", maxTokens: 8192),
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
        if let data = try? Data(contentsOf: self.url),
           let decoded = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = LLMConfig()
        }
    }

    public static var defaultDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Mindo", isDirectory: true)
    }

    public func save() throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(config)
        try data.write(to: url, options: .atomic)
    }

    public func setProviderMeta(_ meta: ProviderMeta, for providerID: GenAIProviderID) {
        config.providers[providerID.rawValue] = meta
        try? save()
    }

    public func providerMeta(for providerID: GenAIProviderID) -> ProviderMeta {
        var meta = config.providers[providerID.rawValue] ?? ProviderMeta()
        if meta.endpoint.isEmpty { meta.endpoint = providerID.defaultEndpoint }
        return meta
    }

    /// All known models for a provider — built-ins first, then user's customs.
    public func allModels(for providerID: GenAIProviderID) -> [ModelMeta] {
        let builtin = BuiltInModels.models(for: providerID)
        let custom = config.customModels[providerID.rawValue] ?? []
        return builtin + custom
    }

    public func addCustomModel(_ model: ModelMeta, for providerID: GenAIProviderID) {
        var list = config.customModels[providerID.rawValue] ?? []
        list.removeAll { $0.name == model.name }
        list.append(model)
        config.customModels[providerID.rawValue] = list
        try? save()
    }
}
