//
//  CloudClients.swift
//  cluelyopen
//
//  Bring-your-own-key cloud LLM clients, each conforming to LLMClient so the
//  AnswerEngine treats them identically to the local OllamaClient. All requests
//  are HTTPS to the provider's own endpoint using the user's API key; nothing
//  goes through any OpenCluely server.
//

import Foundation
import OpenCluelyCore

// MARK: - Anthropic (Claude)

/// Anthropic Messages API. Non-streaming for simplicity (buffered), matching
/// how OllamaClient currently works. Endpoint + headers per the Claude API.
final class AnthropicClient: LLMClient {
    private let apiKey: String
    private let session: URLSession
    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func chat(system: String, user: String, model: String, images: [Data]) async throws -> AsyncThrowingStream<String, Error> {
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
            "system": system,
            "messages": [["role": "user", "content": content]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await send(req, via: session, provider: "Anthropic")
                    // Response: { "content": [ { "type":"text", "text":"..." } ] }
                    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let blocks = obj?["content"] as? [[String: Any]] ?? []
                    let text = blocks.compactMap { $0["text"] as? String }.joined()
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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

    func chat(system: String, user: String, model: String, images: [Data]) async throws -> AsyncThrowingStream<String, Error> {
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

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await send(req, via: session, provider: "OpenAI")
                    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let choices = obj?["choices"] as? [[String: Any]] ?? []
                    let text = choices.compactMap {
                        ($0["message"] as? [String: Any])?["content"] as? String
                    }.joined()
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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

    func chat(system: String, user: String, model: String, images: [Data]) async throws -> AsyncThrowingStream<String, Error> {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var parts: [[String: Any]] = [["text": user]]
        for data in images {
            parts.append(["inline_data": ["mime_type": "image/png",
                                          "data": data.base64EncodedString()]])
        }

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": parts]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await send(req, via: session, provider: "Gemini")
                    // candidates[0].content.parts[].text
                    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let candidates = obj?["candidates"] as? [[String: Any]] ?? []
                    let content = candidates.first?["content"] as? [String: Any]
                    let respParts = content?["parts"] as? [[String: Any]] ?? []
                    let text = respParts.compactMap { $0["text"] as? String }.joined()
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Shared request handling

/// Sends a cloud request, retrying transient failures (rate limits, overloaded
/// models) with a short backoff. A final non-2xx becomes `LLMError.api` carrying
/// the provider's own error message so the overlay can show what went wrong.
private func send(_ req: URLRequest, via session: URLSession, provider: String) async throws -> Data {
    let retryable: Set<Int> = [429, 500, 502, 503, 504]
    let backoffSeconds: [UInt64] = [1, 2]  // waits before the 2nd and 3rd attempts
    var attempt = 0
    while true {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              !(200...299).contains(http.statusCode) else { return data }
        if retryable.contains(http.statusCode), attempt < backoffSeconds.count {
            NSLog("OpenCluely %@: HTTP %d, retrying", provider, http.statusCode)
            try await Task.sleep(nanoseconds: backoffSeconds[attempt] * 1_000_000_000)
            attempt += 1
            continue
        }
        throw LLMError.api(provider: provider, status: http.statusCode,
                           message: apiErrorMessage(from: data))
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
