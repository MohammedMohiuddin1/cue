import Foundation

public enum AnswerContext {
    case none
    case text(String)
    case image(Data)
}

public final class AnswerEngine {
    private let client: LLMClient
    private let modes: ModesManager
    private let settings: Settings

    public init(client: LLMClient, modes: ModesManager, settings: Settings) {
        self.client = client
        self.modes = modes
        self.settings = settings
    }

    public func answer(userText: String, context: AnswerContext) -> AsyncThrowingStream<String, Error> {
        let mode = modes.activeMode
        let contextText: String?
        let images: [Data]
        let model: String
        switch context {
        case .none:
            contextText = nil; images = []; model = settings.textModel
        case .text(let t):
            contextText = t; images = []; model = settings.textModel
        case .image(let d):
            contextText = nil; images = [d]; model = settings.visionModel
        }
        let prompt = PromptBuilder.build(mode: mode, userText: userText, contextText: contextText)

        // Always prepend the user's persistent reference materials (resume,
        // project notes) so the model can answer resume/project questions.
        var system = prompt.system
        let materials = settings.referenceMaterials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !materials.isEmpty {
            system = "Reference material about the user (their resume / projects). "
                   + "Use it when relevant:\n\(materials)\n\n" + system
        }
        let client = self.client
        let finalSystem = system

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = try await client.chat(system: finalSystem, user: prompt.user, model: model, images: images)
                    for try await tok in stream { continuation.yield(tok) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
