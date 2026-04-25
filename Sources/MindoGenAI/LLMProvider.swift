import Foundation

/// Output adjustment hint passed alongside an LLM input. Mirrors `OutputAdjust`.
public enum OutputAdjust: String, Codable, Sendable {
    case asCode
    case asText
    case asParagraph
}

/// Per-request input. Mirrors `GenAiEvents.Input`.
public struct LLMInput: Sendable {
    public let providerID: String
    public let model: String
    public let text: String
    public let temperature: Float
    public let maxTokens: Int
    public let outputAdjust: OutputAdjust
    public let outputLanguage: String?
    public let isRetry: Bool
    public let isStreaming: Bool

    public init(
        providerID: String,
        model: String,
        text: String,
        temperature: Float = 0.7,
        maxTokens: Int = 2048,
        outputAdjust: OutputAdjust = .asText,
        outputLanguage: String? = nil,
        isRetry: Bool = false,
        isStreaming: Bool = true
    ) {
        self.providerID = providerID
        self.model = model
        self.text = text
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.outputAdjust = outputAdjust
        self.outputLanguage = outputLanguage
        self.isRetry = isRetry
        self.isStreaming = isStreaming
    }
}

/// One chunk of streamed (or one full predict) output. Mirrors `StreamPartial`.
public struct StreamPartial: Sendable, Equatable {
    public let text: String
    public let outputTokens: Int
    public let isStop: Bool
    public let isError: Bool

    public init(text: String, outputTokens: Int = 0, isStop: Bool = false, isError: Bool = false) {
        self.text = text
        self.outputTokens = outputTokens
        self.isStop = isStop
        self.isError = isError
    }

    public static let stop = StreamPartial(text: "", isStop: true)
}

/// Per-provider connection configuration. Mirrors `ProviderMeta`.
public struct ProviderMeta: Codable, Hashable, Sendable {
    public var apiKey: String
    public var endpoint: String

    public init(apiKey: String = "", endpoint: String = "") {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }
}

/// Per-model configuration. Mirrors `ModelMeta`.
public struct ModelMeta: Codable, Hashable, Sendable {
    public var name: String
    public var maxTokens: Int
    public var supportsStreaming: Bool
    public var aliases: [String]

    public init(name: String, maxTokens: Int = 4096, supportsStreaming: Bool = true, aliases: [String] = []) {
        self.name = name
        self.maxTokens = maxTokens
        self.supportsStreaming = supportsStreaming
        self.aliases = aliases
    }
}

/// Built-in providers, keyed by stable string IDs that survive across renames.
/// Mirrors `GenAiModelProvider`.
public enum GenAIProviderID: String, CaseIterable, Codable, Sendable {
    case openAI    = "OPEN_AI"
    case gemini    = "GEMINI"
    case qwen      = "ALI_Q_WEN"
    case ollama    = "OLLAMA"
    case huggingFace = "HUGGING_FACE"
    case chatGLM   = "CHAT_GLM"
    case deepSeek  = "DEEP_SEEK"
    case moonshot  = "MOONSHOT"

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .qwen: return "Alibaba Qwen"
        case .ollama: return "Ollama"
        case .huggingFace: return "Hugging Face"
        case .chatGLM: return "ChatGLM"
        case .deepSeek: return "DeepSeek"
        case .moonshot: return "Moonshot"
        }
    }

    public var defaultEndpoint: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .qwen: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .huggingFace: return "https://api-inference.huggingface.co"
        case .chatGLM: return "https://open.bigmodel.cn/api/paas/v4"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .moonshot: return "https://api.moonshot.cn/v1"
        }
    }
}

/// Errors thrown by providers.
public enum LLMError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpStatus(Int, body: String)
    case decoding(String)
    case cancelled
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Missing API key for provider"
        case .invalidURL: return "Invalid endpoint URL"
        case .httpStatus(let s, let b): return "HTTP \(s): \(b.prefix(300))"
        case .decoding(let s): return "Decoding error: \(s)"
        case .cancelled: return "Request was cancelled"
        case .transport(let s): return s
        }
    }
}

/// LLM provider protocol. Mirrors `LlmProvider`.
public protocol LLMProvider: AnyObject, Sendable {
    var providerID: GenAIProviderID { get }
    var meta: ProviderMeta { get }
    var model: ModelMeta { get }

    /// Single-shot prediction.
    func predict(_ input: LLMInput) async throws -> StreamPartial

    /// Streaming prediction. `onPartial` is called on the main actor for each chunk.
    func stream(_ input: LLMInput, onPartial: @escaping @Sendable (StreamPartial) -> Void) async throws

    /// Cancel any in-flight request.
    func cancel()
}
