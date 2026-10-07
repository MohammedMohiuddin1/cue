import Foundation

/// Classifies a user question so the answer style can adapt: coding questions
/// get code + complexity; behavioral/resume/conceptual questions get a natural,
/// conversational answer (no forced code), even inside a coding-focused Mode.
public enum QuestionKind: Equatable, Sendable {
    case coding        // implement / solve / algorithm → code + complexity
    case behavioral    // tell me about yourself / projects / experience → conversational
    case conceptual    // explain / what is / difference → explain, code only if it clarifies

    /// Short name shown in the overlay.
    public var label: String {
        switch self {
        case .coding: return "coding"
        case .behavioral: return "behavioral"
        case .conceptual: return "conceptual"
        }
    }

    /// Coding answers need the model's full reasoning to be correct; behavioral
    /// and conceptual answers barely improve with it, so they ask for less.
    public var reasoningEffort: ReasoningEffort {
        self == .coding ? .standard : .low
    }

    /// A one-line style directive appended to the system prompt for this kind.
    public var styleDirective: String {
        switch self {
        case .coding:
            return """
            This is a coding/DSA question. Reply with exactly this and nothing else:
            Say: "<one or two sentences, first person, that they can say out loud before coding: the approach they're thinking of taking and why, e.g. "I'm thinking of using a hash map so each lookup is O(1)...">"
            <the code>
            Time: <complexity> · Space: <complexity>
            """
        case .behavioral:
            return """
            This is a behavioral / resume / personal question. Answer in the first person, as the candidate speaking in an interview. Do NOT write code or complexity analysis unless explicitly asked.
            If the reference material or prepared STAR stories contain a relevant experience, build the answer from it and keep its real details.
            If nothing relevant is there, give a strong best-practice answer the user can personalize. Never invent employers, projects, dates or numbers; put a [bracketed placeholder] where their own example goes.
            Reply with exactly this and nothing else, under 70 words in total, with each bullet under 12 words:
            Say: "<one sentence opening they can say word for word>"
            • <situation and task>
            • <what they did>
            • <the result>
            Close: "<one sentence wrap-up>"
            """
        case .conceptual:
            return "This is a conceptual question. Answer in 2 to 4 sentences. Include a short code example only if it genuinely aids understanding; do not force code or complexity analysis."
        }
    }

    /// Classify from the question text using simple keyword heuristics (works on
    /// small local models without an extra LLM call).
    public static func classify(_ text: String) -> QuestionKind {
        match(text) ?? .conceptual
    }

    /// Detect the kind from what was actually asked. `question` is the typed
    /// question or a fixed button prompt; `context` is the transcript or screen
    /// text. A typed question is checked first (`questionFirst: true`). A fixed
    /// button prompt says nothing about the real question, so the context is
    /// checked first, using whichever signal appears latest in it — in a
    /// transcript, the interviewer's most recent question wins.
    public static func detect(question: String, context: String?, questionFirst: Bool) -> QuestionKind {
        let fromQuestion = { match(question) }
        let fromContext = { context.flatMap(latestMatch) }
        let found = questionFirst ? (fromQuestion() ?? fromContext())
                                  : (fromContext() ?? fromQuestion())
        return found ?? .conceptual
    }

    /// Whether speech heard since the last answer contains a question worth
    /// answering automatically: a question mark or a known question phrase, and
    /// at least five words, so fillers like "right?" don't trigger an answer.
    public static func looksLikeQuestion(_ speech: String) -> Bool {
        let words = speech.split(whereSeparator: \.isWhitespace).count
        guard words >= 5 else { return false }
        return speech.contains("?") || latestMatch(speech) != nil
    }

    // Checked in this order; earlier groups win when a text matches several.
    private static let signals: [(QuestionKind, [String])] = [
        // Behavioral / resume / project signals.
        (.behavioral, [
            "tell me about", "tell me some", "walk me through", "your project", "your projects",
            "my project", "my projects", "your experience", "my experience", "your resume",
            "my resume", "why did you", "why do you", "describe a time", "describe your",
            "strength", "weakness", "challenge you", "conflict", "yourself",
            "worked on", "have you built", "have you made", "you have made", "you have built",
            "about you", "your background", "your role", "your contribution"
        ]),
        // Coding signals.
        (.coding, [
            "implement", "write a function", "write code", "code for", "solve", "leetcode",
            "algorithm", "time complexity", "space complexity", "big o", "reverse a",
            "given an array", "given a string", "given a", "return the", "find the",
            "two sum", "linked list", "binary tree", "sort", "recursion", "dynamic programming"
        ]),
        // Softer behavioral signals, checked after coding so "how do you reverse
        // a linked list" stays a coding question.
        (.behavioral, [
            "how do you", "how would you handle", "what would you do", "a time when",
            "a time you", "why should we hire", "why this company", "want to work here",
            "where do you see yourself", "what motivates", "your approach to",
            "mistake", "teammate", "your manager", "deadline", "leadership"
        ]),
        // Conceptual signals.
        (.conceptual, [
            "explain", "what is", "what are", "difference between", "how does", "how do",
            "why is", "compare", "when should", "pros and cons", "trade-off", "tradeoff"
        ]),
    ]

    /// The first group with any keyword in `text`, or nil if none match.
    static func match(_ text: String) -> QuestionKind? {
        let q = text.lowercased()
        return signals.first { $0.1.contains(where: q.contains) }?.0
    }

    /// The kind of the last sentence that matches any group. Within a sentence
    /// the usual group order applies, so "tell me about a time you had to explain
    /// X" stays behavioral even though "explain" comes later.
    static func latestMatch(_ text: String) -> QuestionKind? {
        let sentences = text.split(whereSeparator: { ".?!".contains($0) })
        for sentence in sentences.reversed() {
            if let kind = match(String(sentence)) { return kind }
        }
        return nil
    }
}
