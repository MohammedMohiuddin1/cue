import Testing
@testable import OpenCluelyCore

@Test func defaultActiveIsGeneral() {
    let m = ModesManager(store: InMemoryStore())
    #expect(m.activeMode.id == "general")
}

@Test func builtInModesAreCodingFocused() {
    let m = ModesManager(store: InMemoryStore())
    #expect(m.builtInModes.map(\.id) == ["general", "coding-interview", "system-design", "dsa"])
}

@Test func generalHasEmptyPrompt() {
    let m = ModesManager(store: InMemoryStore())
    let general = m.builtInModes.first { $0.id == "general" }
    #expect(general?.systemPrompt.isEmpty == true)
}

@Test func codingModesHaveNonEmptyPrompts() {
    let m = ModesManager(store: InMemoryStore())
    for mode in m.builtInModes where mode.id != "general" {
        #expect(!mode.systemPrompt.isEmpty)
    }
}

@Test func setActivePersists() {
    let store = InMemoryStore()
    let m = ModesManager(store: store)
    m.setActive(id: "dsa")
    let reloaded = ModesManager(store: store)
    #expect(reloaded.activeMode.id == "dsa")
}

@Test func setActiveIgnoresUnknownID() {
    let m = ModesManager(store: InMemoryStore())
    m.setActive(id: "nonexistent")
    #expect(m.activeMode.id == "general")
}
