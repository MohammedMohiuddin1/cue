import Testing
import Foundation
@testable import OpenCluelyCore

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func makeSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: cfg)
}

// StubURLProtocol uses shared mutable static state, so these tests must not
// run concurrently with each other (Swift Testing parallelizes by default).
@Suite(.serialized)
struct OllamaClientTests {

    @Test func streamsTokensInOrder() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.responseData = """
        {"message":{"content":"Hello"},"done":false}
        {"message":{"content":" world"},"done":true}
        """.data(using: .utf8)!
        let client = OllamaClient(baseURL: URL(string: "http://localhost:11434")!, session: makeSession())
        var out = ""
        let stream = try await client.chat(system: "s", user: "u", model: "m", images: [])
        for try await tok in stream { out += tok }
        #expect(out == "Hello world")
    }

    @Test func http404MapsToModelMissing() async {
        StubURLProtocol.statusCode = 404
        StubURLProtocol.responseData = Data()
        let client = OllamaClient(baseURL: URL(string: "http://localhost:11434")!, session: makeSession())
        await #expect(throws: LLMError.modelMissing("ghost")) {
            let stream = try await client.chat(system: "s", user: "u", model: "ghost", images: [])
            for try await _ in stream {}
        }
    }

    @Test func http500MapsToHTTPError() async {
        StubURLProtocol.statusCode = 500
        StubURLProtocol.responseData = Data()
        let client = OllamaClient(baseURL: URL(string: "http://localhost:11434")!, session: makeSession())
        await #expect(throws: LLMError.http(500)) {
            let stream = try await client.chat(system: "s", user: "u", model: "m", images: [])
            for try await _ in stream {}
        }
    }
}
