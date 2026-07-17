public enum PromptBuilder {
    static let baseline = "You are Cue, a concise technical interview assistant. Answer directly and correctly. Show code when relevant."

    public static func build(mode: Mode, userText: String, contextText: String?) -> (system: String, user: String) {
        let system: String
        if mode.systemPrompt.isEmpty {
            system = baseline
        } else {
            system = baseline + "\n\n" + mode.systemPrompt
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
