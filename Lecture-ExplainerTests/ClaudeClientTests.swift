//
//  ClaudeClientTests.swift
//  Lexia
//

import Testing
@testable import Lecture_Explainer
import Foundation

/// The Claude client without the network: stream parsing, error mapping, the
/// request it builds, and full streaming runs against a fake server (MockURLProtocol).
/// No real request is sent and no API key is needed.
struct ClaudeStreamParsingTests {
    @Test func readsTextAndSkipsEverythingElse() {
        #expect(ClaudeStreamEvent.parse(#"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}"#) == .text("Hello"))
        #expect(ClaudeStreamEvent.parse(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#) == nil)
        #expect(ClaudeStreamEvent.parse("event: content_block_delta") == nil)
        #expect(ClaudeStreamEvent.parse("") == nil)
        #expect(ClaudeStreamEvent.parse(#"data: {"type":"ping"}"#) == nil)
        #expect(ClaudeStreamEvent.parse("data: not json") == nil)
    }

    @Test func readsStopReasonAndErrors() {
        #expect(ClaudeStreamEvent.parse(#"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}"#) == .stopReason("end_turn"))
        #expect(ClaudeStreamEvent.parse(#"data: {"type":"message_stop"}"#) == .messageStop)
        #expect(ClaudeStreamEvent.parse(#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
                == .error(type: "overloaded_error", message: "Overloaded"))
    }

    @Test func mapsErrorsByTypeThenStatus() {
        #expect(ClaudeError.from(type: "authentication_error", message: "", status: 401) == .invalidAPIKey)
        #expect(ClaudeError.from(type: "rate_limit_error", message: "", status: 429, retryAfter: 30) == .rateLimited(retryAfter: 30))
        #expect(ClaudeError.from(type: "overloaded_error", message: "", status: nil) == .overloaded)   // in-stream: no status
        #expect(ClaudeError.from(type: nil, message: "too big", status: 413) == .requestTooLarge)    // no JSON body
        #expect(ClaudeError.from(type: "invalid_request_error", message: "bad", status: 400) == .badRequest("bad"))
        let noCredit = "Your credit balance is too low to access the Anthropic API."
        #expect(ClaudeError.from(type: "invalid_request_error", message: noCredit, status: 400) == .billing(noCredit))
        #expect(ClaudeError.overloaded.isRetryable)
        #expect(!ClaudeError.invalidAPIKey.isRetryable)
    }
}

struct ClaudeRequestTests {
    func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func buildsHeadersAndBody() throws {
        let client = ClaudeClient(apiKey: "sk-test")
        let request = try client.makeURLRequest(ClaudeRequest(model: .opus, effort: .high,
                                                              system: "Be brief.", userText: "Hi"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let json = try body(of: request)
        #expect(json["model"] as? String == "claude-opus-5-5")
        #expect(json["stream"] as? Bool == true)
        #expect(json["system"] as? String == "Be brief.")
        #expect(json["fallbacks"] as? String == "default")
        #expect((json["output_config"] as? [String: String])?["effort"] == "high")
        let content = try #require((json["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        #expect(content.count == 1)
        #expect(content[0]["type"] as? String == "text")
        #expect(content[0]["text"] as? String == "Hi")
    }

    @Test func sendsPDFsBeforeTheTextWithACacheMarker() throws {
        let request = ClaudeRequest(documents: [ClaudeDocument(title: "Symbols.pdf", data: Data("%PDF".utf8), cacheUpToHere: true),
                                                ClaudeDocument(title: "L01.pdf", data: Data("%PDF-1".utf8))],
                                    userText: "Explain")
        let json = try body(of: try ClaudeClient(apiKey: "k").makeURLRequest(request))
        let content = try #require((json["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["document", "document", "text"])
        let source = try #require(content[0]["source"] as? [String: String])
        #expect(source == ["type": "base64", "media_type": "application/pdf", "data": Data("%PDF".utf8).base64EncodedString()])
        #expect(content[0]["title"] as? String == "Symbols.pdf")
        #expect((content[0]["cache_control"] as? [String: String]) == ["type": "ephemeral"])
        #expect(content[1]["cache_control"] == nil)
    }

    @Test func leavesOutWhatAModelDoesNotSupport() throws {
        let request = try ClaudeClient(apiKey: "k").makeURLRequest(ClaudeRequest(model: .haiku, userText: "Hi"))
        let json = try body(of: request)
        #expect(json["fallbacks"] == nil)        // Haiku has no server-side fallback
        #expect(json["system"] == nil)           // nil is left out, not sent as null
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }
}

/// A fake server: every request made through `MockURLProtocol.session` gets the
/// canned `reply` instead of going to the network. URLProtocol is the standard
/// hook for this in URLSession.
final class MockURLProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = ""
    }
    nonisolated(unsafe) static var reply = Reply()

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.reply
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// .serialized: these tests share MockURLProtocol.reply, so they must not run at the same time.
@Suite(.serialized)
struct ClaudeStreamingTests {
    func run(_ reply: MockURLProtocol.Reply) async throws -> String {
        MockURLProtocol.reply = reply
        let client = ClaudeClient(apiKey: "sk-test", session: MockURLProtocol.session)
        var text = ""
        for try await piece in client.stream(ClaudeRequest(userText: "Hi")) { text += piece }
        return text
    }

    /// A shortened copy of a real stream: thinking first, then text in pieces.
    let okStream = """
    event: message_start
    data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[]}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}

    event: ping
    data: {"type":"ping"}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" world"}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}

    event: message_stop
    data: {"type":"message_stop"}

    """

    @Test func collectsTheStreamedText() async throws {
        #expect(try await run(.init(body: okStream)) == "Hello world")
    }

    @Test func httpErrorBecomesReadableError() async {
        let reply = MockURLProtocol.Reply(
            status: 429, headers: ["retry-after": "12"],
            body: #"{"type":"error","error":{"type":"rate_limit_error","message":"Slow down"}}"#)
        await #expect(throws: ClaudeError.rateLimited(retryAfter: 12)) { try await run(reply) }
    }

    @Test func refusalStopsTheStream() async {
        let body = """
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Partial"}}

        data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}

        """
        await #expect(throws: ClaudeError.refused) { try await run(.init(body: body)) }
    }

    @Test func errorInsideTheStream() async {
        let body = #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"# + "\n"
        await #expect(throws: ClaudeError.overloaded) { try await run(.init(body: body)) }
    }
}

// .serialized and its own account name, so it can't touch a real saved key.
@Suite(.serialized)
struct KeychainStoreTests {
    let account = "test-account"

    @Test func savesReplacesReadsAndDeletes() throws {
        try KeychainStore.delete(account: account)
        #expect(KeychainStore.read(account: account) == nil)
        try KeychainStore.save("first", account: account)
        try KeychainStore.save("second", account: account)   // replaces, no duplicate error
        #expect(KeychainStore.read(account: account) == "second")
        try KeychainStore.delete(account: account)
        #expect(KeychainStore.read(account: account) == nil)
        try KeychainStore.delete(account: account)            // deleting nothing is fine
    }
}
