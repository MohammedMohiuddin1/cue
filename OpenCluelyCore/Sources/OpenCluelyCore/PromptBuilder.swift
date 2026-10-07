public enum PromptBuilder {
    static func baseline(language: String) -> String {
        "You are Cue, a concise technical interview assistant. Answer directly and correctly. Be brief: the user reads this mid-interview. No preamble, don't restate the question, no headings. Show code when relevant. Write all code in \(language) unless the user explicitly asks for another language, even if the screen shows a different language selected."
    }

    public static func build(mode: Mode, userText: String, contextText: String?,
                             language: String = "Python") -> (system: String, user: String) {
        let base = baseline(language: language)
        let system: String
        if mode.systemPrompt.isEmpty {
            system = base
        } else {
            system = base + "\n\n" + mode.systemPrompt
        }

        let user: String
        if let ctx = contextText, !ctx.isEmpty {
            user = "Context from the interview:\n\(ctx)\n\nQuestion: \(userText)"
        } else {
            user = userText
        }
        return (system, user)
    }
}
