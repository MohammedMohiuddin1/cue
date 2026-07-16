import Foundation

public final class ModesManager {
    private let store: KeyValueStore

    public let builtInModes: [Mode] = [
        Mode(id: "general", name: "General", systemPrompt: ""),
        Mode(id: "coding-interview", name: "Coding Interview",
             systemPrompt: "You are helping in a live coding interview. Give the correct, idiomatic solution with brief reasoning. State time and space complexity. Prefer clean, runnable code."),
        Mode(id: "system-design", name: "System Design",
             systemPrompt: "You are helping in a system design interview. Give a structured answer: requirements, high-level design, data model, scaling, and trade-offs. Be concise and specific."),
        Mode(id: "dsa", name: "DSA / Competitive",
             systemPrompt: "You are helping with a DSA / competitive programming problem. Identify the pattern, give the optimal approach with complexity, then the full solution code. Be fast and precise."),
    ]

    public init(store: KeyValueStore) {
        self.store = store
    }

    public var activeMode: Mode {
        let id = store.string(forKey: "activeModeID") ?? "general"
        return builtInModes.first { $0.id == id } ?? builtInModes[0]
    }

    public func setActive(id: String) {
        guard builtInModes.contains(where: { $0.id == id }) else { return }
        store.setString(id, forKey: "activeModeID")
    }
}
