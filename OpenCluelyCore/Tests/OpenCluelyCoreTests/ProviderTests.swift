import Testing
@testable import OpenCluelyCore

@Test func providerDefaultsToOllama() {
    let s = Settings(store: InMemoryStore(), tier: .high)
    #expect(s.provider == .ollama)
}

@Test func providerPersists() {
    let store = InMemoryStore()
    let s = Settings(store: store, tier: .high)
    s.provider = .anthropic
    #expect(Settings(store: store, tier: .high).provider == .anthropic)
}

@Test func apiKeysAreStoredPerProvider() {
    let store = InMemoryStore()
    let s = Settings(store: store, tier: .high)
    s.setAPIKey("sk-openai", for: .openai)
    s.setAPIKey("sk-ant", for: .anthropic)
    #expect(s.apiKey(for: .openai) == "sk-openai")
    #expect(s.apiKey(for: .anthropic) == "sk-ant")
    #expect(s.apiKey(for: .gemini) == "")
}

@Test func ollamaNeedsNoKeyOthersDo() {
    #expect(Provider.ollama.needsAPIKey == false)
    #expect(Provider.openai.needsAPIKey == true)
    #expect(Provider.anthropic.needsAPIKey == true)
    #expect(Provider.gemini.needsAPIKey == true)
}
