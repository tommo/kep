import Foundation
import Logging

/// Google Gemini provider — distinct request shape from the OpenAI-compatible
/// base class so it gets its own implementation. Endpoint:
/// `POST {endpoint}/models/{model}:streamGenerateContent?alt=sse&key={key}`
/// (or `:generateContent` for non-streaming).
///
/// Request body:
/// ```json
/// {
///   "contents":[{"role":"user","parts":[{"text":"…"}]}],
///   "generationConfig":{"temperature":0.7,"maxOutputTokens":2048}
/// }
/// ```
///
/// Streaming response is line-delimited SSE; each event holds:
/// ```json
/// {"candidates":[{"content":{"role":"model","parts":[{"text":"…"}]},"finishReason":"STOP"|null}]}
/// ```
public final class GeminiProvider: LLMProvider, @unchecked Sendable {
    public let providerID: GenAIProviderID = .gemini
    public var meta: ProviderMeta
    public var model: ModelMeta

    private let logger = Logger(label: "mindo.genai.gemini")
    private let session: URLSession
    private var inFlight: Task<Void, Never>?

    public init(meta: ProviderMeta, model: ModelMeta, session: URLSession = .shared) {
        self.meta = meta
        self.model = model
        self.session = session
    }

    public func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }

    // MARK: - URL building

    private var basePath: String {
        let trimmed = meta.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? GenAIProviderID.gemini.defaultEndpoint : trimmed
    }

    private func endpoint(for action: String, model: String) throws -> URL {
        guard !meta.apiKey.isEmpty else { throw LLMError.missingAPIKey }
        var components = URLComponents(string: "\(basePath)/models/\(model):\(action)")
        components?.queryItems = [URLQueryItem(name: "key", value: meta.apiKey)]
        if action == "streamGenerateContent" {
            components?.queryItems?.append(URLQueryItem(name: "alt", value: "sse"))
        }
        guard let url = components?.url else { throw LLMError.invalidURL }
        return url
    }

    // MARK: - Body

    public static func makeBody(_ input: LLMInput) -> [String: Any] {
        return [
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": input.text]]
                ]
            ],
            "generationConfig": [
                "temperature": input.temperature,
                "maxOutputTokens": input.maxTokens,
            ],
        ]
    }

    private func request(action: String, input: LLMInput) throws -> URLRequest {
        var req = URLRequest(url: try endpoint(for: action, model: input.model))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: Self.makeBody(input))
        return req
    }

    // MARK: - Predict (one-shot)

    public func predict(_ input: LLMInput) async throws -> StreamPartial {
        let req = try request(action: "generateContent", input: input)
        let (data, response) = try await session.data(for: req)
        try LLMHTTP.checkResponse(response, body: String(data: data, encoding: .utf8) ?? "")
        return try Self.parsePredictResponse(data)
    }

    // MARK: - Stream

    public func stream(_ input: LLMInput, onPartial: @escaping @Sendable (StreamPartial) -> Void) async throws {
        let req = try request(action: "streamGenerateContent", input: input)
        let (bytes, response) = try await session.bytes(for: req)
        try await LLMHTTP.checkStreamResponse(response, bytes: bytes)
        try await LLMHTTP.runSSEStream(bytes: bytes, onPartial: onPartial, parseEvent: Self.parseStreamEvent)
    }

    // MARK: - Response parsing (testable)

    public static func parsePredictResponse(_ data: Data) throws -> StreamPartial {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decoding("expected JSON object")
        }
        if let err = obj["error"] as? [String: Any], let message = err["message"] as? String {
            throw LLMError.decoding(message)
        }
        let candidates = obj["candidates"] as? [[String: Any]] ?? []
        guard let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw LLMError.decoding("no candidate content")
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        let usage = obj["usageMetadata"] as? [String: Any]
        let outTokens = (usage?["candidatesTokenCount"] as? Int) ?? 0
        return StreamPartial(text: text, outputTokens: outTokens, isStop: true)
    }

    public static func parseStreamEvent(_ json: String) -> StreamPartial? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let candidates = obj["candidates"] as? [[String: Any]] ?? []
        guard let first = candidates.first else { return nil }
        let content = first["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]] ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        let finishReason = first["finishReason"] as? String
        let isStop = finishReason != nil && finishReason != ""
        let usage = obj["usageMetadata"] as? [String: Any]
        let outTokens = (usage?["candidatesTokenCount"] as? Int) ?? 0
        return StreamPartial(text: text, outputTokens: outTokens, isStop: isStop)
    }
}
