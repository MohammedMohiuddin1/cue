import Foundation

public enum LLMError: Error, Equatable {
    case notRunning
    case modelMissing(String)
    case http(Int)
    /// A cloud provider rejected the request; `message` is the provider's own explanation.
    /// `status` is 0 when the error arrived mid-stream rather than as an HTTP status.
    case api(provider: String, status: Int, message: String)
}

/// How much reasoning to ask the model for. Coding answers keep the provider's
/// default; behavioral and conceptual answers ask for less so they arrive sooner.
/// Providers or models without a reasoning control ignore it.
public enum ReasoningEffort: Sendable, Equatable {
    case low
    case standard
}

public protocol LLMClient: Sendable {
    func chat(system: String, user: String, model: String, images: [Data],
              effort: ReasoningEffort) async throws -> AsyncThrowingStream<String, Error>
}

public extension LLMClient {
    func chat(system: String, user: String, model: String, images: [Data]) async throws -> AsyncThrowingStream<String, Error> {
        try await chat(system: system, user: user, model: model, images: images, effort: .standard)
    }
}
