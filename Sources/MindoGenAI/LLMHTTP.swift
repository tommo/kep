import Foundation

/// Shared HTTP-status validation for the LLM providers. Each `predict` /
/// `stream` opens the same way: read URLResponse, ensure it's an HTTPURLResponse,
/// fail when status isn't 2xx, drain the body for the error message.
enum LLMHTTP {

    /// Validate that `response` is an HTTPURLResponse with a 2xx status.
    /// `body` is only evaluated on the failure path so callers can pass the
    /// already-loaded data without forcing a string conversion when we'd
    /// throw it away.
    static func checkResponse(
        _ response: URLResponse,
        body: @autoclosure () -> String
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.httpStatus(http.statusCode, body: body())
        }
    }

    /// Streaming variant — when status isn't 2xx, drain the byte sequence
    /// so we can include the server's error message in the thrown error.
    static func checkStreamResponse(
        _ response: URLResponse,
        bytes: URLSession.AsyncBytes
    ) async throws {
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            var collected = Data()
            for try await b in bytes { collected.append(b) }
            throw LLMError.httpStatus(http.statusCode, body: String(data: collected, encoding: .utf8) ?? "")
        }
    }
}
