//
//  Transcriber.swift
//  cluelyopen
//
//  Speech-to-text abstraction. WhisperTranscriber (bundled whisper.cpp) is
//  wired in a later step; StubTranscriber lets us verify the audio→Listen
//  pipeline end-to-end before whisper is integrated.
//

import Foundation

/// Turns 16 kHz mono float PCM samples into recognized English text.
protocol Transcriber {
    func transcribe(_ pcm: [Float]) async -> String
}

/// Temporary placeholder used until whisper.cpp is bundled.
/// It reports how much audio it received so we can confirm capture works,
/// without producing real transcription yet.
final class StubTranscriber: Transcriber {
    func transcribe(_ pcm: [Float]) async -> String {
        // Emit nothing per-chunk; capture verification happens via the
        // AudioCapture level callback + status line, not fake text.
        return ""
    }
}
