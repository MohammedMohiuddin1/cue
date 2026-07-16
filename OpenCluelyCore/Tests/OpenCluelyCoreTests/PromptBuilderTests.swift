import Testing
@testable import OpenCluelyCore

private let coding = Mode(id: "coding-interview", name: "Coding Interview", systemPrompt: "CODING PROMPT")
private let general = Mode(id: "general", name: "General", systemPrompt: "")

@Test func modePromptIncludedInSystem() {
    let p = PromptBuilder.build(mode: coding, userText: "solve this", contextText: nil)
    #expect(p.system.contains("CODING PROMPT"))
}

@Test func generalModeStillHasBaselineSystem() {
    let p = PromptBuilder.build(mode: general, userText: "hi", contextText: nil)
    #expect(!p.system.isEmpty)
}

@Test func contextIncludedInUser() {
    let p = PromptBuilder.build(mode: coding, userText: "what's the answer?", contextText: "Two Sum problem")
    #expect(p.user.contains("Two Sum problem"))
    #expect(p.user.contains("what's the answer?"))
}

@Test func noContextUserIsJustUserText() {
    let p = PromptBuilder.build(mode: coding, userText: "just this", contextText: nil)
    #expect(p.user == "just this")
}

@Test func emptyContextTreatedAsNoContext() {
    let p = PromptBuilder.build(mode: coding, userText: "q", contextText: "")
    #expect(p.user == "q")
}
