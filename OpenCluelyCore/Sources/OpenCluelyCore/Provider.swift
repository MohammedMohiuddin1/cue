import Foundation

/// Where inference runs. Ollama is fully local (default); the others are
/// bring-your-own-key cloud providers reached over HTTPS.
public enum Provider: String, CaseIterable, Sendable {
    case ollama      // local, no key
    case openai      // BYOK
    case anthropic   // BYOK
    case gemini      // BYOK

    public var displayName: String {
        switch self {
        case .ollama: return "Ollama (local)"
        case .openai: return "OpenAI (GPT)"
        case .anthropic: return "Anthropic (Claude)"
        case .gemini: return "Google (Gemini)"
        }
    }

    /// Cloud providers need an API key; Ollama does not.
    public var needsAPIKey: Bool { self != .ollama }

    /// A sensible default text model per provider (user-editable in Settings).
    public var defaultTextModel: String {
        switch self {
        case .ollama: return "qwen2.5-coder:7b"
        case .openai: return "gpt-5"
        case .anthropic: return "claude-opus-4-8"
        case .gemini: return "gemini-flash-latest"
        }
    }

    /// A default vision-capable model per provider.
    public var defaultVisionModel: String {
        switch self {
        case .ollama: return "llava"
        case .openai: return "gpt-5"
        case .anthropic: return "claude-opus-4-8"
        case .gemini: return "gemini-flash-latest"
        }
    }
}
