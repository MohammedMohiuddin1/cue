import Testing
import Foundation
@testable import OpenCluelyCore

final class FakeLLM: LLMClient, @unchecked Sendable {
    var lastModel = ""
    var lastImages: [Data] = []
    var lastSystem = ""
    var lastUser = ""
    var toEmit: [String] = ["ok"]
    var lastEffort: ReasoningEffort?
    var errorToThrow: Error?

    func chat(system: String, user: String, model: String, images: [Data],
              effort: ReasoningEffort) async throws -> AsyncThrowingStream<String, Error> {
        lastModel = model; lastImages = images; lastSystem = system; lastUser = user; lastEffort = effort
        let emit = toEmit
        let err = errorToThrow
        return AsyncThrowingStream { c in
            if let err { c.finish(throwing: err); return }
            for t in emit { c.yield(t) }
            c.finish()
        }
    }
}

private func makeEngine(_ fake: FakeLLM) -> AnswerEngine {
    let store = InMemoryStore()
    return AnswerEngine(client: fake,
                        modes: ModesManager(store: store),
                        settings: Settings(store: store, tier: .high))
}

@Test func noneContextUsesTextModelNoImages() async throws {
    let fake = FakeLLM()
    var out = ""
    for try await t in makeEngine(fake).answer(userText: "q", context: .none) { out += t }
    #expect(out == "ok")
    #expect(fake.lastModel == "qwen2.5-coder:7b")
    #expect(fake.lastImages.isEmpty)
}

@Test func textContextUsesTextModelAndIncludesContext() async throws {
    let fake = FakeLLM()
    for try await _ in makeEngine(fake).answer(userText: "help", context: .text("Two Sum")) {}
    #expect(fake.lastModel == "qwen2.5-coder:7b")
    #expect(fake.lastUser.contains("Two Sum"))
    #expect(fake.lastImages.isEmpty)
}

@Test func imageContextUsesVisionModelAndPassesImage() async throws {
    let fake = FakeLLM()
    let img = Data([0x1, 0x2, 0x3])
    for try await _ in makeEngine(fake).answer(userText: "q", context: .image(img)) {}
    #expect(fake.lastModel == "qwen2.5vl:7b")
    #expect(fake.lastImages == [img])
}

@Test func activeModePromptFlowsIntoSystem() async throws {
    let fake = FakeLLM()
    let store = InMemoryStore()
    let modes = ModesManager(store: store)
    modes.setActive(id: "dsa")
    let engine = AnswerEngine(client: fake, modes: modes, settings: Settings(store: store, tier: .high))
    for try await _ in engine.answer(userText: "q", context: .none) {}
    #expect(fake.lastSystem.contains("DSA"))
}

@Test func referenceMaterialsIncludedInSystemPrompt() async throws {
    let fake = FakeLLM()
    let store = InMemoryStore()
    let settings = Settings(store: store, tier: .high)
    settings.referenceMaterials = "RESUME: Built a distributed cache at Acme."
    let engine = AnswerEngine(client: fake, modes: ModesManager(store: store), settings: settings)
    for try await _ in engine.answer(userText: "tell me about your projects", context: .none) {}
    #expect(fake.lastSystem.contains("distributed cache at Acme"))
}

@Test func emptyReferenceMaterialsNotInjected() async throws {
    let fake = FakeLLM()
    for try await _ in makeEngine(fake).answer(userText: "q", context: .none) {}
    #expect(!fake.lastSystem.contains("Reference material"))
}

@Test func errorsPropagate() async {
    let fake = FakeLLM()
    fake.errorToThrow = LLMError.notRunning
    await #expect(throws: LLMError.notRunning) {
        for try await _ in makeEngine(fake).answer(userText: "q", context: .none) {}
    }
}

@Test func codeLanguageSettingFlowsIntoSystem() async throws {
    let fake = FakeLLM()
    let store = InMemoryStore()
    let settings = Settings(store: store, tier: .high)
    for try await _ in AnswerEngine(client: fake, modes: ModesManager(store: store), settings: settings)
        .answer(userText: "q", context: .none) {}
    #expect(fake.lastSystem.contains("Write all code in Python"))

    settings.codeLanguage = "Java"
    for try await _ in AnswerEngine(client: fake, modes: ModesManager(store: store), settings: settings)
        .answer(userText: "q", context: .none) {}
    #expect(fake.lastSystem.contains("Write all code in Java"))
}

@Test func codingQuestionsUseStandardEffortOthersLow() async throws {
    let fake = FakeLLM()
    let engine = makeEngine(fake)
    for try await _ in engine.answer(userText: "implement quicksort", context: .none) {}
    #expect(fake.lastEffort == .standard)
    for try await _ in engine.answer(userText: "tell me about yourself", context: .none) {}
    #expect(fake.lastEffort == .low)
}

@Test func explicitKindOverridesDetection() async throws {
    let fake = FakeLLM()
    for try await _ in makeEngine(fake).answer(userText: "Answer or solve the question shown on the screen.",
                                               context: .text("tell me about yourself"),
                                               kind: .behavioral) {}
    #expect(fake.lastSystem.contains("behavioral"))
    #expect(fake.lastEffort == .low)
}

@Test func starStoriesOnlySentWithBehavioralQuestions() async throws {
    let fake = FakeLLM()
    let store = InMemoryStore()
    let settings = Settings(store: store, tier: .high)
    settings.starStories = "### Tell me about yourself.\nSituation: STORY-MARKER"
    let engine = AnswerEngine(client: fake, modes: ModesManager(store: store), settings: settings)

    for try await _ in engine.answer(userText: "tell me about yourself", context: .none) {}
    #expect(fake.lastSystem.contains("STORY-MARKER"))

    for try await _ in engine.answer(userText: "implement quicksort", context: .none) {}
    #expect(!fake.lastSystem.contains("STORY-MARKER"))
}

@Test func generateStarStoriesSendsResumeAndQuestions() async throws {
    let fake = FakeLLM()
    for try await _ in makeEngine(fake).generateStarStories(resume: "Built a distributed cache at Acme.") {}
    #expect(fake.lastUser.contains("distributed cache at Acme"))
    #expect(fake.lastUser.contains(StarStories.commonQuestions[0]))
    #expect(fake.lastSystem.contains("Never invent"))
    // Questions the resume can't answer get coaching instead of an empty slot.
    #expect(fake.lastSystem.contains("How to answer"))
}
