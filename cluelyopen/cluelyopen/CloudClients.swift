//
//  CloudClients.swift
//  cluelyopen
//
//  Bring-your-own-key cloud LLM clients, each conforming to LLMClient so the
//  AnswerEngine treats them identically to the local OllamaClient. All requests
//  are HTTPS to the provider's own endpoint using the user's API key; nothing
//  goes through any OpenCluely server. Responses stream as server-sent events,
//  so text appears in the overlay as it is generated.
//

import Foundation
import OpenCluelyCore

// MARK: - Anthropic (Claude)

/// Anthropic Messages API, streamed. Endpoint + headers per the Claude API.
/// `effort` is ignored: extended thinking is off unless requested, so answers
/// already come back without a reasoning pass.
final class AnthropicClient: LLMClient {
    private let apiKey: String
    private let session: URLSession
    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func chat(system: String, user: String, model: String, images: [Data],
              effort: ReasoningEffort) async throws -> AsyncThrowingStream<String, Error> {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        var content: [[String: Any]] = images.map { data in
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/png",
                        "data": data.base64EncodedString()]]
        }
        content.append(["type": "text", "text": user])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "stream": true,
            "system": system,
            "messages": [["role": "user", "content": content]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Event: { "type":"content_block_delta", "delta": { "type":"text_delta", "text":"..." } }
        return streamEvents(req, via: session, provider: "Anthropic") { event in
            guard event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta" else { return nil }
            return delta["text"] as? String
        }
    }
}

// MARK: - OpenAI (and OpenAI-compatible endpoints)

final class OpenAIClient: LLMClient {
    private let apiKey: String
    private let session: URLSession
    private let baseURL: URL
    init(apiKey: String, session: URLSession = .shared,
         baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    func chat(system: String, user: String, model: String, images: [Data],
              effort: ReasoningEffort) async throws -> AsyncThrowingStream<String, Error> {
        var req = URLRequest(url: baseURL.appendingPathComponent("/chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Vision: user content becomes an array of text + image_url parts.
        let userContent: Any
        if images.isEmpty {
            userContent = user
        } else {
            var parts: [[String: Any]] = [["type": "text", "text": user]]
            for data in images {
                parts.append(["type": "image_url",
                              "image_url": ["url": "data:image/png;base64,\(data.base64EncodedString())"]])
            }
            userContent = parts
        }

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]
        // Only reasoning models accept reasoning_effort; others reject the field.
        if effort == .low && (model.hasPrefix("gpt-5") || model.hasPrefix("o")) {
            body["reasoning_effort"] = "low"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Event: { "choices": [ { "delta": { "content": "..." } } ] }
        return streamEvents(req, via: session, provider: "OpenAI") { event in
            let choices = event["choices"] as? [[String: Any]] ?? []
            return (choices.first?["delta"] as? [String: Any])?["content"] as? String
        }
    }
}

// MARK: - Google (Gemini)

final class GeminiClient: LLMClient {
    private let apiKey: String
    private let session: URLSession
    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func chat(system: String, user: String, model: String, images: [Data],
              effort: ReasoningEffort) async throws -> AsyncThrowingStream<String, Error> {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var parts: [[String: Any]] = [["text": user]]
        for data in images {
            parts.append(["inline_data": ["mime_type": "image/png",
                                          "data": data.base64EncodedString()]])
        }

        var body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": parts]],
        ]
        // Gemini 3+ models think before answering by default; "low" skips most of
        // that. Gemini 2.x models use a different control, so leave them alone.
        if effort == .low && !model.hasPrefix("gemini-2") {
            body["generationConfig"] = ["thinkingConfig": ["thinkingLevel": "low"]]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Event: { "candidates": [ { "content": { "parts": [ { "text": "..." } ] } } ] }
        return streamEvents(req, via: session, provider: "Gemini") { event in
            let candidates = event["candidates"] as? [[String: Any]] ?? []
            let content = candidates.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]] ?? []
            return parts.filter { $0["thought"] as? Bool != true }
                        .compactMap { $0["text"] as? String }.joined()
        }
    }
}

// MARK: - Shared request handling

/// Streams a server-sent-events response, yielding the text `extract` pulls out
/// of each `data:` event. An `{"error": ...}` event mid-stream becomes
/// `LLMError.api` with status 0.
private func streamEvents(_ req: URLRequest, via session: URLSession, provider: String,
                          extract: @escaping @Sendable ([String: Any]) -> String?) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let bytes = try await openStream(req, via: session, provider: provider)
                for try await line in bytes.lines {
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8),
                          let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }
                    if let error = event["error"] as? [String: Any] {
                        throw LLMError.api(provider: provider, status: 0,
                                           message: error["message"] as? String ?? "Unknown error")
                    }
                    if let text = extract(event), !text.isEmpty { continuation.yield(text) }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// Opens a streaming request, retrying transient server failures (overloaded
/// models, gateway errors) with a short backoff. Retries happen before any text
/// has arrived, so nothing is shown twice. 429 is not retried: quota limits reset
/// in minutes to hours, and each retry would count against the quota. A final
/// non-2xx becomes `LLMError.api` carrying the provider's own error message so
/// the overlay can show what went wrong.
private func openStream(_ req: URLRequest, via session: URLSession,
                        provider: String) async throws -> URLSession.AsyncBytes {
    let retryable: Set<Int> = [500, 502, 503, 504]
    let backoffSeconds: [UInt64] = [1, 2]  // waits before the 2nd and 3rd attempts
    var attempt = 0
    while true {
        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse,
              !(200...299).contains(http.statusCode) else { return bytes }
        if retryable.contains(http.statusCode), attempt < backoffSeconds.count {
            NSLog("OpenCluely %@: HTTP %d, retrying", provider, http.statusCode)
            try await Task.sleep(nanoseconds: backoffSeconds[attempt] * 1_000_000_000)
            attempt += 1
            continue
        }
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count >= 8192 { break }
        }
        throw LLMError.api(provider: provider, status: http.statusCode,
                           message: apiErrorMessage(from: body))
    }
}

/// Anthropic, OpenAI and Gemini all return `{ "error": { "message": "..." } }`.
private func apiErrorMessage(from data: Data) -> String {
    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    if let message = (obj?["error"] as? [String: Any])?["message"] as? String {
        return message
    }
    return String(decoding: data.prefix(200), as: UTF8.self)
}

// MARK: - Factory

enum LLMClientFactory {
    /// Build the client for the active provider. Cloud providers use the stored
    /// API key; Ollama uses the local endpoint.
    @MainActor
    static func make(for settings: Settings) -> LLMClient {
        switch settings.provider {
        case .ollama:
            return OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!)
        case .openai:
            return OpenAIClient(apiKey: settings.apiKey(for: .openai))
        case .anthropic:
            return AnthropicClient(apiKey: settings.apiKey(for: .anthropic))
        case .gemini:
            return GeminiClient(apiKey: settings.apiKey(for: .gemini))
        }
    }
}
