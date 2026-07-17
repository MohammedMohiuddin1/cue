import Testing
@testable import OpenCluelyCore

@Test func classifiesBehavioralProjectQuestions() {
    #expect(QuestionKind.classify("tell me about some of the projects you have made") == .behavioral)
    #expect(QuestionKind.classify("tell me about your EnVision project") == .behavioral)
    #expect(QuestionKind.classify("walk me through your experience") == .behavioral)
    #expect(QuestionKind.classify("what's your biggest weakness?") == .behavioral)
    #expect(QuestionKind.classify("tell me about yourself") == .behavioral)
}

@Test func classifiesCodingQuestions() {
    #expect(QuestionKind.classify("reverse a linked list in python") == .coding)
    #expect(QuestionKind.classify("implement quicksort") == .coding)
    #expect(QuestionKind.classify("given an array, find two numbers summing to target") == .coding)
    #expect(QuestionKind.classify("write a function to check a palindrome") == .coding)
}

@Test func classifiesConceptualQuestions() {
    #expect(QuestionKind.classify("explain how a hashmap works") == .conceptual)
    #expect(QuestionKind.classify("what is the difference between a process and a thread") == .conceptual)
}

@Test func behavioralDirectiveForbidsForcedCode() {
    #expect(QuestionKind.behavioral.styleDirective.lowercased().contains("do not write code"))
}
