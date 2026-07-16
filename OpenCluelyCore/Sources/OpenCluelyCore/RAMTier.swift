import Foundation

public enum RAMTier: Equatable {
    case low, mid, high

    public static func tier(forGB gb: Int) -> RAMTier {
        if gb >= 16 { return .high }
        if gb >= 8 { return .mid }
        return .low
    }

    public static func detected() -> RAMTier {
        let bytes = ProcessInfo.processInfo.physicalMemory
        let gb = Int(bytes / 1_073_741_824)
        return tier(forGB: gb)
    }
}
