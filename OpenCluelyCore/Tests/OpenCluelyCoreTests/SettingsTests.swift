import Testing
import Foundation
@testable import OpenCluelyCore

final class InMemoryStore: KeyValueStore {
    var dict: [String: Any] = [:]
    func string(forKey k: String) -> String? { dict[k] as? String }
    func setString(_ v: String, forKey k: String) { dict[k] = v }
    func double(forKey k: String) -> Double? { dict[k] as? Double }
    func setDouble(_ v: Double, forKey k: String) { dict[k] = v }
}

@Test func defaultsForHighRAM() {
    let s = Settings(store: InMemoryStore(), tier: .high)
    #expect(s.textModel == "qwen3-coder")
    #expect(s.visionModel == "qwen2.5vl:7b")
    #expect(s.whisperModel == "base.en")
}

@Test func defaultsForMidRAM() {
    let s = Settings(store: InMemoryStore(), tier: .mid)
    #expect(s.textModel == "deepseek-coder-v2")
    #expect(s.visionModel == "qwen2.5vl:7b")
}

@Test func defaultsForLowRAM() {
    let s = Settings(store: InMemoryStore(), tier: .low)
    #expect(s.textModel == "deepseek-coder-v2")
    #expect(s.visionModel == "moondream")
}

@Test func persistsTextModel() {
    let store = InMemoryStore()
    let s = Settings(store: store, tier: .high)
    s.textModel = "deepseek-r1"
    let reloaded = Settings(store: store, tier: .high)
    #expect(reloaded.textModel == "deepseek-r1")
}

@Test func persistsOverlayOrigin() {
    let store = InMemoryStore()
    let s = Settings(store: store, tier: .high)
    s.overlayOrigin = CGPoint(x: 300, y: 400)
    let reloaded = Settings(store: store, tier: .high)
    let expected = CGPoint(x: 300, y: 400)
    #expect(reloaded.overlayOrigin.x == expected.x)
    #expect(reloaded.overlayOrigin.y == expected.y)
}
