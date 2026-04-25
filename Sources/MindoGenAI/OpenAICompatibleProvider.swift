import Foundation
import Logging

/// Base class for OpenAI-compatible chat completion endpoints (OpenAI, Ollama,
/// DeepSeek, Moonshot, Qwen DashScope's compatible mode). Subclasses tweak
/// authentication, model defaults, and request adjustments.
open class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {
    public let providerID: GenAIProviderID
    public var meta: ProviderMeta
    public var model: ModelMeta

    private let logger: Logger
    private let session: URLSession
    private var inFlight: URLSessionDataTask?
    private var inFlightStream: Task<Void, Never>?

    public init(providerID: GenAIProviderID, meta: ProviderMeta, model: ModelMeta, session: URLSession = .shared) {
        self.providerID = providerID
        self.meta = meta
        self.model = model
        self.logger = Logger(label: "mindo.genai.\(providerID.rawValue)")
        self.session = session
    }

    open func cancel() {
        inFlight?.cancel()
        inFlightStream?.cancel()
        inFlight = nil
        inFlightStream = nil
    }

    // MARK: - URL building

    open var endpoint: URL {
        get throws {
            let trimmed = meta.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: trimmed.isEmpty ? providerID.defaultEndpoint : trimmed) else {
                throw LLMError.invalidURL
            }
            return url.appendingPathComponent("chat/completions")
        }
    }

    open func makeRequest(_ input: LLMInput, streaming: Bool) throws -> URLRequest {
        var req = URLRequest(url: try endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !meta.apiKey.isEmpty {
            req.setValue("Bearer \(meta.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": input.model,
            "stream": streaming,
            "temperature": input.temperature,
            "max_tokens": input.maxTokens,
            "messages": [
                ["role": "user", "content": input.text]
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    // MARK: - Predict

    open func predict(_ input: LLMInput) async throws -> StreamPartial {
        let req = try makeRequest(input, streaming: false)
        let (data, response) = try await session.data(for: req)
        try LLMHTTP.checkResponse(response, body: String(data: data, encoding: .utf8) ?? "")
        return try Self.parsePredictResponse(data)
    }

    // MARK: - Stream

    open func stream(_ input: LLMInput, onPartial: @escaping @Sendable (StreamPartial) -> Void) async throws {
        let req = try makeRequest(input, streaming: true)
        let (bytes, response) = try await session.bytes(for: req)
        try await LLMHTTP.checkStreamResponse(response, bytes: bytes)

        var parser = SSEParser()
        var totalText = ""
        var totalTokens = 0
        for try await line in bytes.lines {
            // `URLSession.bytes(for:).lines` already splits by newline, but SSE
            // events are delimited by *blank* lines. We re-introduce the
            // newline so the parser can find the `\n\n` block separator.
            let events = parser.append(line + "\n")
            for ev in events {
                if ev.data == "[DONE]" {
                    onPartial(StreamPartial(text: totalText, outputTokens: totalTokens, isStop: true))
                    return
                }
                if let partial = Self.parseStreamEvent(ev.data) {
                    if !partial.text.isEmpty { totalText.append(partial.text) }
                    if partial.outputTokens > 0 { totalTokens = partial.outputTokens }
                    onPartial(partial)
                    if partial.isStop { return }
                }
            }
        }
        onPartial(StreamPartial(text: totalText, outputTokens: totalTokens, isStop: true))
    }

    // MARK: - Response parsing (shared helpers, exposed for testing)

    public static func parsePredictResponse(_ data: Data) throws -> StreamPartial {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decoding("expected JSON object")
        }
        let usage = obj["usage"] as? [String: Any]
        let outTokens = (usage?["completion_tokens"] as? Int) ?? 0
        if let choices = obj["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return StreamPartial(text: content, outputTokens: outTokens, isStop: true)
        }
        // Fall back to top-level error fields.
        if let err = obj["error"] as? [String: Any], let message = err["message"] as? String {
            throw LLMError.decoding(message)
        }
        throw LLMError.decoding("unrecognized response shape")
    }

    public static func parseStreamEvent(_ json: String) -> StreamPartial? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let choices = obj["choices"] as? [[String: Any]]
        guard let first = choices?.first else { return nil }
        let delta = (first["delta"] as? [String: Any]) ?? (first["message"] as? [String: Any]) ?? [:]
        let text = (delta["content"] as? String) ?? ""
        let finishReason = first["finish_reason"] as? String
        let isStop = finishReason != nil
        let usage = obj["usage"] as? [String: Any]
        let outTokens = (usage?["completion_tokens"] as? Int) ?? 0
        return StreamPartial(text: text, outputTokens: outTokens, isStop: isStop)
    }
}
