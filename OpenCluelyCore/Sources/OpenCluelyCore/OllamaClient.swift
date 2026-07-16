import Foundation

public final class OllamaClient: LLMClient {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://localhost:11434")!,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func chat(system: String, user: String, model: String, images: [Data]) async throws -> AsyncThrowingStream<String, Error> {
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var userMessage: [String: Any] = ["role": "user", "content": user]
        if !images.isEmpty {
            userMessage["images"] = images.map { $0.base64EncodedString() }
        }
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": system],
                userMessage
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let session = self.session
        let requestedModel = model
        let finalRequest = req
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (data, response) = try await session.data(for: finalRequest)
                    if let http = response as? HTTPURLResponse {
                        switch http.statusCode {
                        case 200: break
                        case 404: throw LLMError.modelMissing(requestedModel)
                        default: throw LLMError.http(http.statusCode)
                        }
                    }
                    let text = String(decoding: data, as: UTF8.self)
                    for line in text.split(separator: "\n") {
                        guard let lineData = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let msg = obj["message"] as? [String: Any],
                              let content = msg["content"] as? String else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
