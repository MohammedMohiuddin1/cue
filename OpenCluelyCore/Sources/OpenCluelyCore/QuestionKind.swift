import Foundation

/// Classifies a user question so the answer style can adapt: coding questions
/// get code + complexity; behavioral/resume/conceptual questions get a natural,
/// conversational answer (no forced code), even inside a coding-focused Mode.
public enum QuestionKind: Equatable {
    case coding        // implement / solve / algorithm → code + complexity
    case behavioral    // tell me about yourself / projects / experience → conversational
    case conceptual    // explain / what is / difference → explain, code only if it clarifies

    /// A one-line style directive appended to the system prompt for this kind.
    public var styleDirective: String {
        switch self {
        case .coding:
            return "This is a coding/DSA question: give a correct, idiomatic code solution and state time and space complexity."
        case .behavioral:
            return "This is a behavioral / resume / project question. Answer conversationally in the first person, as the candidate speaking in an interview. Draw on the reference material about the user. Do NOT write code or complexity analysis unless explicitly asked."
        case .conceptual:
            return "This is a conceptual question. Explain clearly and concisely. Include a short code example only if it genuinely aids understanding; do not force code or complexity analysis."
        }
    }

    /// Classify from the question text using simple keyword heuristics (works on
    /// small local models without an extra LLM call).
    public static func classify(_ text: String) -> QuestionKind {
        let q = text.lowercased()

        // Behavioral / resume / project signals.
        let behavioral = [
            "tell me about", "tell me some", "walk me through", "your project", "your projects",
            "my project", "my projects", "your experience", "my experience", "your resume",
            "my resume", "why did you", "why do you", "describe a time", "describe your",
            "strength", "weakness", "challenge you", "conflict", "yourself",
            "worked on", "have you built", "have you made", "you have made", "you have built",
            "about you", "your background", "your role", "your contribution"
        ]
        if behavioral.contains(where: q.contains) { return .behavioral }

        // Coding signals.
        let coding = [
            "implement", "write a function", "write code", "code for", "solve", "leetcode",
            "algorithm", "time complexity", "space complexity", "big o", "reverse a",
            "given an array", "given a string", "given a", "return the", "find the",
            "two sum", "linked list", "binary tree", "sort", "recursion", "dynamic programming"
        ]
        if coding.contains(where: q.contains) { return .coding }

        // Conceptual signals.
        let conceptual = [
            "explain", "what is", "what are", "difference between", "how does", "how do",
            "why is", "compare", "when should", "pros and cons", "trade-off", "tradeoff"
        ]
        if conceptual.contains(where: q.contains) { return .conceptual }

        // Default: conceptual (safe, doesn't force code).
        return .conceptual
    }
}
