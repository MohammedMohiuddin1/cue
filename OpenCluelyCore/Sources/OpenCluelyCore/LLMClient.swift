import Foundation

public enum LLMError: Error, Equatable {
    case notRunning
    case modelMissing(String)
    case http(Int)
}

public protocol LLMClient {
    func chat(system: String, user: String, model: String, images: [Data]) async throws -> AsyncThrowingStream<String, Error>
}
