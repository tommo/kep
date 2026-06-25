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
        self.logger = Logger(label: "kep.genai.\(providerID.rawValue)")
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
            guard let url = URL(string: meta.resolvedBase(default: providerID.defaultEndpoint)) else {
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
        var body: [String: Any] = [
            "model": input.model,
            "stream": streaming,
            "temperature": input.temperature,
            "max_tokens": input.maxTokens,
            "messages": input.wireMessages.map(Self.wireMessage),
        ]
        if let tools = input.tools, !tools.isEmpty {
            body["tools"] = tools.map { spec -> [String: Any] in
                let schema = (try? JSONSerialization.jsonObject(with: Data(spec.parametersJSON.utf8)))
                    ?? ["type": "object", "properties": [:]]
                return ["type": "function",
                        "function": ["name": spec.name, "description": spec.description, "parameters": schema]]
            }
            body["tool_choice"] = "auto"
        }
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

    /// One non-streaming completion returning BOTH assistant text and any
    /// requested tool calls — the unit the agent tool-loop runs on.
    open func complete(_ input: LLMInput) async throws -> (text: String, toolCalls: [ToolCall]) {
        let req = try makeRequest(input, streaming: false)
        let (data, response) = try await session.data(for: req)
        try LLMHTTP.checkResponse(response, body: String(data: data, encoding: .utf8) ?? "")
        let calls = Self.parseToolCalls(data)
        let text = (try? Self.parsePredictResponse(data).text) ?? ""
        return (text, calls)
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
           let message = first["message"] as? [String: Any] {
            // Reasoning models (deepseek-reasoner / -v4-flash) put the answer in
            // `content`, but when it's empty fall back to `reasoning_content` so
            // the reply isn't silently dropped.
            let content = (message["content"] as? String) ?? ""
            let reasoning = (message["reasoning_content"] as? String) ?? ""
            return StreamPartial(text: content.isEmpty ? reasoning : content, outputTokens: outTokens, isStop: true)
        }
        // Fall back to top-level error fields.
        if let err = obj["error"] as? [String: Any], let message = err["message"] as? String {
            throw LLMError.decoding(message)
        }
        throw LLMError.decoding("unrecognized response shape")
    }

    /// Serialize one chat message to the OpenAI wire shape, including
    /// assistant `tool_calls` and `tool` result messages.
    static func wireMessage(_ m: ChatMessage) -> [String: Any] {
        var d: [String: Any] = ["role": m.role.rawValue, "content": m.content]
        if let calls = m.toolCalls, !calls.isEmpty {
            d["tool_calls"] = calls.map { c -> [String: Any] in
                ["id": c.id, "type": "function",
                 "function": ["name": c.name, "arguments": c.argumentsJSON]]
            }
        }
        if let id = m.toolCallID { d["tool_call_id"] = id }
        if let name = m.name { d["name"] = name }
        return d
    }

    /// Extract any `tool_calls` the model requested from a (non-streaming)
    /// chat-completion response. Empty when the model returned plain content.
    public static func parseToolCalls(_ data: Data) -> [ToolCall] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let calls = message["tool_calls"] as? [[String: Any]] else { return [] }
        return calls.compactMap { call in
            guard let fn = call["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return nil }
            let id = (call["id"] as? String) ?? name
            let args = (fn["arguments"] as? String) ?? "{}"
            return ToolCall(id: id, name: name, argumentsJSON: args)
        }
    }

    public static func parseStreamEvent(_ json: String) -> StreamPartial? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let choices = obj["choices"] as? [[String: Any]]
        guard let first = choices?.first else { return nil }
        let delta = (first["delta"] as? [String: Any]) ?? (first["message"] as? [String: Any]) ?? [:]
        // Stream the answer; while a reasoning model is still "thinking" its
        // deltas carry only `reasoning_content`, so surface that too (otherwise
        // the panel shows nothing until/unless content arrives).
        let content = (delta["content"] as? String) ?? ""
        let reasoning = (delta["reasoning_content"] as? String) ?? ""
        let text = content.isEmpty ? reasoning : content
        let finishReason = first["finish_reason"] as? String
        let isStop = finishReason != nil
        let usage = obj["usage"] as? [String: Any]
        let outTokens = (usage?["completion_tokens"] as? Int) ?? 0
        return StreamPartial(text: text, outputTokens: outTokens, isStop: isStop)
    }
}
