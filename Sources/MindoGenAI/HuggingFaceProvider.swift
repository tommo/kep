import Foundation
import Logging

/// HuggingFace Inference API — distinct from both OpenAI-compat and Gemini.
/// Endpoint: `POST {endpoint}/models/{model}` with optional `?stream=true`
/// for SSE streaming.
///
/// Request:
/// ```json
/// {"inputs": "…", "parameters": {"temperature": 0.7, "max_new_tokens": 2048,
///                                 "return_full_text": false}}
/// ```
///
/// Non-streaming response: `[{"generated_text": "…"}]` (array of one object).
/// Streaming SSE: each `data:` payload is
/// `{"token": {"text": "…", "special": false}, "generated_text": null}`
/// with a final event carrying the full `generated_text`.
public final class HuggingFaceProvider: LLMProvider, @unchecked Sendable {
    public let providerID: GenAIProviderID = .huggingFace
    public var meta: ProviderMeta
    public var model: ModelMeta

    private let logger = Logger(label: "mindo.genai.huggingface")
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

    private var basePath: String {
        let trimmed = meta.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? GenAIProviderID.huggingFace.defaultEndpoint : trimmed
    }

    private func endpoint(model: String, streaming: Bool) throws -> URL {
        var components = URLComponents(string: "\(basePath)/models/\(model)")
        if streaming {
            components?.queryItems = [URLQueryItem(name: "stream", value: "true")]
        }
        guard let url = components?.url else { throw LLMError.invalidURL }
        return url
    }

    public static func makeBody(_ input: LLMInput, streaming: Bool) -> [String: Any] {
        var parameters: [String: Any] = [
            "temperature": input.temperature,
            "max_new_tokens": input.maxTokens,
            "return_full_text": false,
        ]
        if streaming { parameters["stream"] = true }
        return [
            "inputs": input.text,
            "parameters": parameters,
        ]
    }

    private func request(_ input: LLMInput, streaming: Bool) throws -> URLRequest {
        var req = URLRequest(url: try endpoint(model: input.model, streaming: streaming))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !meta.apiKey.isEmpty {
            req.setValue("Bearer \(meta.apiKey)", forHTTPHeaderField: "Authorization")
        }
        if streaming {
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: Self.makeBody(input, streaming: streaming))
        return req
    }

    // MARK: - Predict

    public func predict(_ input: LLMInput) async throws -> StreamPartial {
        let req = try request(input, streaming: false)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.httpStatus(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.parsePredictResponse(data)
    }

    // MARK: - Stream

    public func stream(_ input: LLMInput, onPartial: @escaping @Sendable (StreamPartial) -> Void) async throws {
        let req = try request(input, streaming: true)
        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw LLMError.transport("No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            var collected = Data()
            for try await b in bytes { collected.append(b) }
            throw LLMError.httpStatus(http.statusCode, body: String(data: collected, encoding: .utf8) ?? "")
        }

        var parser = SSEParser()
        var totalText = ""
        for try await line in bytes.lines {
            let events = parser.append(line + "\n")
            for ev in events {
                if let partial = Self.parseStreamEvent(ev.data) {
                    if !partial.text.isEmpty { totalText.append(partial.text) }
                    onPartial(partial)
                    if partial.isStop { return }
                }
            }
        }
        onPartial(StreamPartial(text: totalText, isStop: true))
    }

    // MARK: - Response parsing (testable)

    public static func parsePredictResponse(_ data: Data) throws -> StreamPartial {
        // HF returns either an array (`[{"generated_text": "..."}]`) or an
        // error object (`{"error": "..."}`). Accept both shapes.
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = array.first, let text = first["generated_text"] as? String {
            return StreamPartial(text: text, isStop: true)
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? String {
                throw LLMError.decoding(err)
            }
            // Some HF spaces return a single object directly.
            if let text = obj["generated_text"] as? String {
                return StreamPartial(text: text, isStop: true)
            }
        }
        throw LLMError.decoding("unrecognized HuggingFace response shape")
    }

    public static func parseStreamEvent(_ json: String) -> StreamPartial? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Per-token chunk:
        // {"token":{"id":1,"text":"…","logprob":-0.4,"special":false},
        //  "generated_text":null,"details":null}
        let token = obj["token"] as? [String: Any]
        let text = (token?["text"] as? String) ?? ""
        let isSpecial = (token?["special"] as? Bool) ?? false
        let finalText = obj["generated_text"] as? String
        let isStop = finalText != nil
        // Don't emit "special" tokens (they're delimiters, not content).
        if isSpecial && !isStop { return StreamPartial(text: "", isStop: false) }
        return StreamPartial(text: text, isStop: isStop)
    }
}
