import Foundation

public enum LLMError: Error, Equatable {
    case notRunning
    case modelMissing(String)
    case http(Int)
    /// A cloud provider rejected the request; `message` is the provider's own explanation.
    case api(provider: String, status: Int, message: String)
}

public protocol LLMClient: Sendable {
    func chat(system: String, user: String, model: String, images: [Data]) async throws -> AsyncThrowingStream<String, Error>
}
