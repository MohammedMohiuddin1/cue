import Foundation

public final class TranscriptBuffer {
    private let maxChars: Int
    private var storage: String = ""

    public init(maxChars: Int = 4000) {
        self.maxChars = maxChars
    }

    public func append(_ text: String) {
        storage += text
        if storage.count > maxChars {
            storage = String(storage.suffix(maxChars))
        }
    }

    public var recent: String { storage }

    public func clear() { storage = "" }
}
