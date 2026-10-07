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

    /// Answer a question. `kind` is the caller's detected question type; when nil
    /// it is detected from the question text, then the context.
    public func answer(userText: String, context: AnswerContext,
                       kind: QuestionKind? = nil) -> AsyncThrowingStream<String, Error> {
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
        let prompt = PromptBuilder.build(mode: mode, userText: userText, contextText: contextText,
                                         language: settings.codeLanguage)

        // Always prepend the user's persistent reference materials (resume,
        // project notes) so the model can answer resume/project questions.
        var system = prompt.system
        var effort = ReasoningEffort.standard

        // Adapt the answer style to the question type so behavioral/resume
        // questions get a conversational answer even in a coding-focused Mode.
        if case .image = context {} else {
            let kind = kind ?? QuestionKind.detect(question: userText, context: contextText,
                                                   questionFirst: true)
            system += "\n\n" + kind.styleDirective
            effort = kind.reasoningEffort
            let stories = settings.starStories.trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == .behavioral && !stories.isEmpty {
                system += "\n\nPrepared STAR stories from the user's resume. Prefer one of these when it fits:\n\(stories)"
            }
        }

        let materials = settings.referenceMaterials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !materials.isEmpty {
            system = "Reference material about the user (their resume / projects). "
                   + "Use it when relevant:\n\(materials)\n\n" + system
        }
        return stream(system: system, user: prompt.user, model: model, images: images, effort: effort)
    }

    /// Write STAR stories for common behavioral questions from the user's resume.
    public func generateStarStories(resume: String) -> AsyncThrowingStream<String, Error> {
        let prompt = StarStories.prompt(resume: resume)
        return stream(system: prompt.system, user: prompt.user, model: settings.textModel,
                      images: [], effort: .standard)
    }

    private func stream(system: String, user: String, model: String, images: [Data],
                        effort: ReasoningEffort) -> AsyncThrowingStream<String, Error> {
        let client = self.client
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = try await client.chat(system: system, user: user, model: model,
                                                       images: images, effort: effort)
                    for try await tok in stream { continuation.yield(tok) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Prepared behavioral answers, generated once from the user's resume so live
/// behavioral questions can draw on ready-made STAR stories.
public enum StarStories {
    public static let commonQuestions = [
        "Tell me about yourself.",
        "Tell me about a project you're proud of.",
        "Tell me about a difficult technical challenge you solved.",
        "Tell me about a time you disagreed with a teammate.",
        "Tell me about a time you failed or made a mistake.",
        "Tell me about a time you worked under a tight deadline.",
        "Tell me about a time you showed leadership.",
        "Tell me about a time you had to learn something new quickly.",
        "Why do you want to work here?",
        "What are your greatest strength and weakness?",
    ]

    public static func prompt(resume: String) -> (system: String, user: String) {
        let system = """
        You write interview preparation notes. Using only the experience in the user's resume, write a STAR story for each question.
        Never invent employers, projects, dates or numbers.
        When the resume has a fitting experience, format it exactly like this, under 120 words:
        ### <question>
        Situation: ...
        Task: ...
        Action: ...
        Result: ...
        Opening line: "..."

        When the resume has nothing that fits, coach the user instead, under 120 words:
        ### <question>
        No matching experience in resume.
        What the interviewer is looking for: <one sentence>
        How to answer:
        - <tip>
        - <tip>
        - <tip>
        Example skeleton: "<a first-person answer with [placeholders] for their own details>"
        """
        let questions = commonQuestions.map { "- \($0)" }.joined(separator: "\n")
        let user = "Resume:\n\(resume)\n\nQuestions:\n\(questions)"
        return (system, user)
    }
}
