import Testing
@testable import OpenCluelyCore

@Test func tierForRAM() {
    #expect(RAMTier.tier(forGB: 16) == .high)
    #expect(RAMTier.tier(forGB: 10) == .mid)
    #expect(RAMTier.tier(forGB: 6) == .low)
}

@Test func tierBoundaries() {
    #expect(RAMTier.tier(forGB: 8) == .mid)   // 8 is the mid floor
    #expect(RAMTier.tier(forGB: 7) == .low)
}
