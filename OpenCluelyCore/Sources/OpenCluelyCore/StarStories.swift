import Foundation

/// Prepared behavioral answers, generated once from the user's resume so live
/// behavioral questions can draw on ready-made STAR stories.
public enum StarStories {
    public static let commonQuestions = [
        "Tell me about yourself.",
        "Tell me about a project you're proud of.",
        "Tell me about a difficult technical challenge you solved.",
        "Tell me about a time you disagreed with a teammate.",
        "Tell me about a time you failed or made a mistake.",
        "Tell me about a time you worked under a tight deadline.",
        "Tell me about a time you showed leadership.",
        "Tell me about a time you had to learn something new quickly.",
        "Why do you want to work here?",
        "What are your greatest strength and weakness?",
    ]

    public static func prompt(resume: String) -> (system: String, user: String) {
        let system = """
        You write interview preparation notes. Using only the experience in the user's resume, write a STAR story for each question.
        Never invent employers, projects, dates or numbers. If the resume has nothing that fits a question, write "No matching experience in resume — add your own." under it.
        Format each one exactly like this, and keep each story under 120 words:
        ### <question>
        Situation: ...
        Task: ...
        Action: ...
        Result: ...
        Opening line: "..."
        """
        let questions = commonQuestions.map { "- \($0)" }.joined(separator: "\n")
        let user = "Resume:\n\(resume)\n\nQuestions:\n\(questions)"
        return (system, user)
    }
}
