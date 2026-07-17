import Foundation

public protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
    func double(forKey key: String) -> Double?
    func setDouble(_ value: Double, forKey key: String)
}

extension UserDefaults: KeyValueStore {
    public func string(forKey key: String) -> String? {
        object(forKey: key) as? String
    }
    public func setString(_ value: String, forKey key: String) {
        set(value, forKey: key)
    }
    public func double(forKey key: String) -> Double? {
        object(forKey: key) as? Double
    }
    public func setDouble(_ value: Double, forKey key: String) {
        set(value, forKey: key)
    }
}

public final class Settings {
    private let store: KeyValueStore
    private let defaultTextModel: String
    private let defaultVisionModel: String

    public init(store: KeyValueStore, tier: RAMTier) {
        self.store = store
        self.defaultTextModel = Self.defaultText(for: tier)
        self.defaultVisionModel = Self.defaultVision(for: tier)
    }

    public var textModel: String {
        get { store.string(forKey: "textModel") ?? defaultTextModel }
        set { store.setString(newValue, forKey: "textModel") }
    }
    public var visionModel: String {
        get { store.string(forKey: "visionModel") ?? defaultVisionModel }
        set { store.setString(newValue, forKey: "visionModel") }
    }
    public var whisperModel: String {
        // base.en — fastest practical model, used with a streaming window for
        // near-real-time transcription. Core ML accelerated. The app bundles
        // ggml-<name>.bin (+ the .mlmodelc encoder). Changeable in Settings.
        get { store.string(forKey: "whisperModel") ?? "base.en" }
        set { store.setString(newValue, forKey: "whisperModel") }
    }
    public var overlayOrigin: CGPoint {
        get {
            let x = store.double(forKey: "overlayX") ?? 200
            let y = store.double(forKey: "overlayY") ?? 200
            return CGPoint(x: x, y: y)
        }
        set {
            store.setDouble(Double(newValue.x), forKey: "overlayX")
            store.setDouble(Double(newValue.y), forKey: "overlayY")
        }
    }

    /// Persistent reference material (resume, project notes) that is always
    /// prepended as context to every answer, so the model knows the user's
    /// background for resume/project questions. Empty by default.
    public var referenceMaterials: String {
        get { store.string(forKey: "referenceMaterials") ?? "" }
        set { store.setString(newValue, forKey: "referenceMaterials") }
    }

    // NOTE: These are the "best free model" recommendations by RAM tier. They
    // are only DEFAULTS — the Settings window lets the user pick any pulled
    // model, and the stored choice overrides these. `qwen3-coder` (~19GB) is the
    // ideal high-tier pick but must be pulled first; users who haven't pulled it
    // change the model in Settings.
    private static func defaultText(for tier: RAMTier) -> String {
        switch tier {
        // qwen2.5-coder:7b is the best coding model that fits comfortably on a
        // 16GB Mac (~4.4GB, leaves OS headroom). qwen3-coder (~19GB) needs 32GB+.
        case .high: return "qwen2.5-coder:7b"
        case .mid, .low: return "qwen2.5-coder:7b"
        }
    }
    private static func defaultVision(for tier: RAMTier) -> String {
        switch tier {
        case .high, .mid: return "qwen2.5vl:7b"
        case .low: return "moondream"
        }
    }
}
