public struct Mode: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let systemPrompt: String

    public init(id: String, name: String, systemPrompt: String) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
    }
}
