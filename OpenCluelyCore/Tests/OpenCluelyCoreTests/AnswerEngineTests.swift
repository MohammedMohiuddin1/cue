import Testing
import Foundation
@testable import OpenCluelyCore

final class FakeLLM: LLMClient, @unchecked Sendable {
    var lastModel = ""
    var lastImages: [Data] = []
    var lastSystem = ""
    var lastUser = ""
    var toEmit: [String] = ["ok"]
    var errorToThrow: Error?

    func chat(system: String, user: String, model: String, images: [Data]) async throws -> AsyncThrowingStream<String, Error> {
        lastModel = model; lastImages = images; lastSystem = system; lastUser = user
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
