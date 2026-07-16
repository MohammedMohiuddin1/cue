import Testing
@testable import OpenCluelyCore

@Test func appendAndRead() {
    let b = TranscriptBuffer(maxChars: 100)
    b.append("hello ")
    b.append("world")
    #expect(b.recent == "hello world")
}

@Test func trimsToMaxChars() {
    let b = TranscriptBuffer(maxChars: 5)
    b.append("abcdefgh")
    #expect(b.recent == "defgh")
}

@Test func trimsAcrossMultipleAppends() {
    let b = TranscriptBuffer(maxChars: 4)
    b.append("ab")
    b.append("cdef")
    #expect(b.recent == "cdef")
}

@Test func clearEmptiesBuffer() {
    let b = TranscriptBuffer(maxChars: 100)
    b.append("data")
    b.clear()
    #expect(b.recent == "")
}
