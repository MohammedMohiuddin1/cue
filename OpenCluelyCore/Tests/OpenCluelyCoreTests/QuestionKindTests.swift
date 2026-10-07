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

@Test func softBehavioralQuestionsAreBehavioral() {
    #expect(QuestionKind.classify("how do you learn emerging technologies") == .behavioral)
    #expect(QuestionKind.classify("why should we hire you") == .behavioral)
    #expect(QuestionKind.classify("how would you handle a missed deadline") == .behavioral)
}

@Test func codingStillWinsOverSoftBehavioral() {
    #expect(QuestionKind.classify("how do you reverse a linked list") == .coding)
}

@Test func buttonPromptDefersToContext() {
    let prompt = "Answer or solve the question shown on the screen."
    #expect(QuestionKind.detect(question: prompt, context: "Tell me about a time you led a team",
                                questionFirst: false) == .behavioral)
    #expect(QuestionKind.detect(question: prompt, context: "Given an array nums, return the indices",
                                questionFirst: false) == .coding)
    // Nothing recognizable in the context: fall back to the prompt.
    #expect(QuestionKind.detect(question: prompt, context: "hello there",
                                questionFirst: false) == .coding)
}

@Test func latestQuestionInTranscriptWins() {
    let transcript = "Tell me about yourself. Great, thanks. Now, given an array of integers, find the two that sum to target."
    #expect(QuestionKind.detect(question: "Answer the most recent question from the conversation.",
                                context: transcript, questionFirst: false) == .coding)
    let reversed = "Given an array, find two numbers. Nice solution. Okay, how do you learn emerging technologies?"
    #expect(QuestionKind.detect(question: "Answer the most recent question from the conversation.",
                                context: reversed, questionFirst: false) == .behavioral)
}

@Test func typedQuestionBeatsContext() {
    #expect(QuestionKind.detect(question: "implement this", context: "tell me about yourself",
                                questionFirst: true) == .coding)
}

@Test func onlyCodingGetsFullReasoning() {
    #expect(QuestionKind.coding.reasoningEffort == .standard)
    #expect(QuestionKind.behavioral.reasoningEffort == .low)
    #expect(QuestionKind.conceptual.reasoningEffort == .low)
}

@Test func autoAnswerTriggersOnRealQuestions() {
    #expect(QuestionKind.looksLikeQuestion("so tell me about a time you disagreed with your manager"))
    #expect(QuestionKind.looksLikeQuestion("what made you choose that particular database?"))
    #expect(QuestionKind.looksLikeQuestion("given an array of integers return the two that sum to target"))
}

@Test func autoAnswerIgnoresFillerAndSmallTalk() {
    #expect(!QuestionKind.looksLikeQuestion("right?"))
    #expect(!QuestionKind.looksLikeQuestion("okay sounds good"))
    #expect(!QuestionKind.looksLikeQuestion("thanks so much for joining us today everyone"))
}

@Test func behavioralFormatIsCapped() {
    #expect(QuestionKind.behavioral.styleDirective.contains("under 70 words"))
}

@Test func laterKeywordInSameSentenceDoesNotOverrideBehavioral() {
    let heard = "the next one is tell me about a time when you had to explain a technical concept to a non-technical person"
    #expect(QuestionKind.detect(question: "Answer the most recent question from the conversation.",
                                context: heard, questionFirst: false) == .behavioral)
}
