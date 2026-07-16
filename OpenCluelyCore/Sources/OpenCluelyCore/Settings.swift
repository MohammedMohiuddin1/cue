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

    private static func defaultText(for tier: RAMTier) -> String {
        switch tier {
        case .high: return "qwen3-coder"
        case .mid, .low: return "deepseek-coder-v2"
        }
    }
    private static func defaultVision(for tier: RAMTier) -> String {
        switch tier {
        case .high, .mid: return "qwen2.5vl:7b"
        case .low: return "moondream"
        }
    }
}
