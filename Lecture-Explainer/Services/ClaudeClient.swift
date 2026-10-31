//
//  ClaudeClient.swift
//  Lexia
//

import Foundation

// Talks to the Claude Messages API (POST https://api.anthropic.com/v1/messages)
// directly with URLSession. There is no official Anthropic SDK for Swift, so this
// file builds the HTTP request and reads the streamed reply itself.
//
// Overview of one request:
//   1. ClaudeClient.makeURLRequest builds the POST: headers (API key, API version)
//      and a JSON body (model, prompt, "stream": true, …).
//   2. The server answers with Server-Sent Events (SSE): a long-lived response
//      where each line is either `event: <name>` or `data: <json>`.
//   3. ClaudeStreamEvent.parse turns each `data:` line into an event; the text
//      pieces are passed on as they arrive, which is what makes the reply appear
//      word by word on screen.
//   4. HTTP errors and in-stream errors become a ClaudeError with a readable message.

/// The models the app offers in Settings.
enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus: "Claude Opus 5.5 (best explanations)"
        case .sonnet: "Claude Sonnet 5.5 (faster, cheaper)"
        case .haiku: "Claude Haiku 5.5 (fastest, cheapest)"
        }
    }

    /// Whether the API can re-run a declined request on another model by itself
    /// (`fallbacks: "default"`). Haiku has no such fallback.
    var supportsFallback: Bool { self != .haiku }
}

/// How much the model thinks before answering: more effort, better reasoning,
/// more tokens (= cost and time). Derivations benefit from "high".
enum ClaudeEffort: String, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
}

/// A PDF sent along with the request. Claude reads both the text and an image of
/// each page, so scanned slides and equations drawn as pictures come through too.
struct ClaudeDocument: Equatable {
    var title: String
    var data: Data
    /// Marks the end of the part of the request that repeats between requests (see
    /// makeURLRequest). Only the last of the repeating documents should have it.
    var cacheUpToHere = false
}

/// What to send. Kept small on purpose: one system prompt and one user message,
/// which holds the PDFs (if any) followed by the text.
struct ClaudeRequest {
    var model: ClaudeModel = .opus
    var effort: ClaudeEffort = .high
    var system: String?
    var documents: [ClaudeDocument] = []
    var userText: String
    /// Upper limit for the reply, thinking included. Streaming allows a large value
    /// without timeouts; a value that's too small cuts the explanation off mid-sentence.
    var maxTokens = 64_000
}

/// Something that went wrong, with a message a user can act on.
enum ClaudeError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case billing(String)
    case permissionDenied(String)
    case notFound(String)
    case requestTooLarge
    case rateLimited(retryAfter: Int?)
    case overloaded
    case server(String)
    case badRequest(String)
    case refused
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No API key yet. Add one in Settings."
        case .invalidAPIKey: "The API key was rejected. Check it in Settings."
        case .billing(let message): "Billing problem on your Anthropic account: \(message)"
        case .permissionDenied(let message): "This key isn't allowed to do that: \(message)"
        case .notFound(let message): "Not found (is the model available to your account?): \(message)"
        case .requestTooLarge: "The request is too large. Try a shorter document."
        case .rateLimited(let seconds):
            "Too many requests right now." + (seconds.map { " Try again in \($0) s." } ?? " Try again shortly.")
        case .overloaded: "Claude is overloaded at the moment. Try again in a minute."
        case .server(let message): "Anthropic server error: \(message)"
        case .badRequest(let message): "The request was invalid: \(message)"
        case .refused: "Claude declined to answer this request."
        case .unexpected(let message): message
        }
    }

    /// Whether trying the same request again later can help.
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .server: true
        default: false
        }
    }

    /// Maps an API error to a case. The `type` string (e.g. "rate_limit_error") is
    /// the reliable signal and also arrives for errors inside a stream, where there is
    /// no HTTP status; the status code is the fallback.
    static func from(type: String?, message: String, status: Int?, retryAfter: Int? = nil) -> ClaudeError {
        switch (type, status) {
        case ("authentication_error", _), (_, 401): .invalidAPIKey
        case ("billing_error", _), (_, 402): .billing(message)
        // An account without credit gets a 400 "invalid_request_error" whose message
        // names the credit balance; it's a billing problem, not a bad request.
        case _ where message.localizedCaseInsensitiveContains("credit balance"): .billing(message)
        case ("permission_error", _), (_, 403): .permissionDenied(message)
        case ("not_found_error", _), (_, 404): .notFound(message)
        case ("request_too_large", _), (_, 413): .requestTooLarge
        case ("rate_limit_error", _), (_, 429): .rateLimited(retryAfter: retryAfter)
        case ("overloaded_error", _), (_, 529): .overloaded
        case ("api_error", _), (_, 500): .server(message)
        case ("invalid_request_error", _), (_, 400): .badRequest(message)
        default: .unexpected(status.map { "HTTP \($0): \(message)" } ?? message)
        }
    }
}

/// One parsed line of the SSE stream that the app cares about.
enum ClaudeStreamEvent: Equatable {
    /// A piece of the answer's text.
    case text(String)
    /// Why the answer ended: "end_turn" (finished), "max_tokens" (cut off), "refusal", …
    case stopReason(String)
    case messageStop
    case error(type: String, message: String)

    // Only the fields the app reads; JSONDecoder ignores everything else.
    private struct Payload: Decodable {
        struct Delta: Decodable {
            var type: String?
            var text: String?
            var stop_reason: String?
        }
        struct ErrorBody: Decodable {
            var type: String
            var message: String
        }
        var type: String
        var delta: Delta?
        var error: ErrorBody?
    }

    /// Parses one line of the stream. Returns nil for lines the app ignores:
    /// `event:` lines (the JSON repeats the event name as "type"), blank separator
    /// lines, `ping` keep-alives, thinking deltas, and start/stop bookkeeping.
    static func parse(_ line: String) -> ClaudeStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)) else { return nil }

        switch payload.type {
        case "content_block_delta":
            // Opus 5.5 always thinks first; its thinking arrives as "thinking_delta"
            // pieces, which are skipped here. Only the answer ("text_delta") is shown.
            if payload.delta?.type == "text_delta", let text = payload.delta?.text { return .text(text) }
            return nil
        case "message_delta":
            return payload.delta?.stop_reason.map { .stopReason($0) }
        case "message_stop":
            return .messageStop
        case "error":
            return payload.error.map { .error(type: $0.type, message: $0.message) }
        default:
            return nil
        }
    }
}

struct ClaudeClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// The API version the request shapes in this file follow. A newer version can
    /// change request or response fields, so it is pinned, not "latest".
    static let apiVersion = "2026-10-21"
    /// Beta flag for `fallbacks: "default"` (see makeURLRequest).
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    let apiKey: String
    var session: URLSession = .shared

    /// A client with the key from the Keychain.
    static func fromKeychain() throws -> ClaudeClient {
        guard let key = KeychainStore.read(), !key.isEmpty else { throw ClaudeError.missingAPIKey }
        return ClaudeClient(apiKey: key)
    }

    // The JSON body. Property names follow the API's snake_case via CodingKeys.
    private struct Body: Encodable {
        struct Message: Encodable {
            var role: String
            var content: [Block]
        }
        /// One piece of a message: {"type": "text", "text": …} or
        /// {"type": "document", "source": {"type": "base64", …}, "title": …}.
        /// Fields that are nil are left out of the JSON.
        struct Block: Encodable {
            struct Source: Encodable {
                var type = "base64"
                var media_type = "application/pdf"
                var data: String
            }
            struct CacheControl: Encodable { var type = "ephemeral" }
            var type: String
            var text: String?
            var source: Source?
            var title: String?
            var cache_control: CacheControl?
        }
        struct OutputConfig: Encodable {
            var effort: String
        }
        var model: String
        var max_tokens: Int
        var stream: Bool
        var system: String?          // left out of the JSON when nil
        var messages: [Message]
        var output_config: OutputConfig
        var fallbacks: String?
    }

    func makeURLRequest(_ request: ClaudeRequest) throws -> URLRequest {
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        // Long answers with thinking can take minutes; the stream keeps the
        // connection busy, but allow a generous gap between pieces.
        urlRequest.timeoutInterval = 300

        // Models can decline a request (stop reason "refusal"). With fallbacks set to
        // "default", the API re-runs a declined request on a suitable other model
        // inside the same call instead of returning nothing.
        let fallbacks: String? = request.model.supportsFallback ? "default" : nil
        if fallbacks != nil {
            urlRequest.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }

        let body = Body(model: request.model.rawValue,
                        max_tokens: request.maxTokens,
                        stream: true,
                        system: request.system,
                        messages: [.init(role: "user", content: Self.blocks(for: request))],
                        // Thinking can't be switched off on Opus 5.5; effort is the dial.
                        output_config: .init(effort: request.effort.rawValue),
                        fallbacks: fallbacks)
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    /// The user message's blocks: PDFs first, then the text, which is the order the
    /// API documentation recommends for documents.
    ///
    /// Prompt caching: the API can remember the start of a request for a few minutes,
    /// and a later request that starts with exactly the same content pays a fraction
    /// of the price for that part. A `cache_control` marker says where the repeating
    /// part ends. When several lectures of a course are explained in a row, the system
    /// prompt and the reference sheet are the same each time, so the marker goes on
    /// the last reference document.
    private static func blocks(for request: ClaudeRequest) -> [Body.Block] {
        let documents = request.documents.map { document in
            Body.Block(type: "document",
                       source: .init(data: document.data.base64EncodedString()),
                       title: document.title,
                       cache_control: document.cacheUpToHere ? .init() : nil)
        }
        return documents + [Body.Block(type: "text", text: request.userText)]
    }

    /// Sends the request and yields the answer's text piece by piece.
    ///
    /// AsyncThrowingStream is Swift's way to return "values over time": the caller
    /// writes `for try await piece in client.stream(request) { … }`. Cancelling the
    /// caller's Task (the Stop button) ends the loop, which cancels the network
    /// request through onTermination.
    func stream(_ request: ClaudeRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw ClaudeError.unexpected("No HTTP response")
                    }
                    guard http.statusCode == 200 else {
                        throw await Self.error(from: bytes, response: http)
                    }
                    for try await line in bytes.lines {
                        switch ClaudeStreamEvent.parse(line) {
                        case .text(let piece):
                            continuation.yield(piece)
                        case .stopReason("refusal"):
                            throw ClaudeError.refused
                        case .error(let type, let message):
                            throw ClaudeError.from(type: type, message: message, status: nil)
                        case .stopReason, .messageStop, nil:
                            continue
                        }
                    }
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads an error response's JSON body:
    /// {"type": "error", "error": {"type": "rate_limit_error", "message": "…"}}
    private static func error(from bytes: URLSession.AsyncBytes, response: HTTPURLResponse) async -> ClaudeError {
        struct ErrorResponse: Decodable {
            struct Inner: Decodable { var type: String; var message: String }
            var error: Inner
        }
        var data = Data()
        do {
            for try await byte in bytes { data.append(byte) }
        } catch {}
        let retryAfter = response.value(forHTTPHeaderField: "retry-after").flatMap { Int($0) }
        let parsed = try? JSONDecoder().decode(ErrorResponse.self, from: data)
        return ClaudeError.from(type: parsed?.error.type,
                                message: parsed?.error.message ?? String(decoding: data, as: UTF8.self),
                                status: response.statusCode,
                                retryAfter: retryAfter)
    }
}
