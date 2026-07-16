//
//  WhisperTranscriber.swift
//  cluelyopen
//
//  Fully-local speech-to-text using bundled whisper.cpp (via SwiftWhisper).
//  Continuously accumulates incoming PCM and transcribes ~6s windows with a
//  short overlap so words at window boundaries aren't lost and no audio is
//  dropped while whisper is busy.
//

import Foundation
import SwiftWhisper

final class WhisperTranscriber: Transcriber {
    private let whisper: Whisper
    private let store = SampleStore(
        windowSamples: 16_000 * 6,   // ~6s window
        hopSamples: 16_000 * 5       // advance ~5s each time (1s overlap)
    )

    /// - Parameter modelURL: path to a ggml whisper model, e.g. ggml-base.en.bin
    init(modelURL: URL) {
        // Force English (bundled model is base.en); without this whisper
        // auto-detects and can mis-detect, producing lossy output.
        let params = WhisperParams(strategy: .greedy)
        params.language = .english
        params.translate = false
        params.no_context = true
        params.suppress_blank = true
        params.single_segment = false
        self.whisper = Whisper(fromFileURL: modelURL, withParams: params)
    }

    func transcribe(_ pcm: [Float]) async -> String {
        // Append; get a window to run only when enough new audio has arrived.
        guard let window = await store.append(pcm) else { return "" }
        do {
            let segments = try await whisper.transcribe(audioFrames: window)
            let text = segments.map(\.text).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("OpenCluely whisper: window %d samples -> \"%@\"", window.count, text)
            return text.isEmpty ? "" : text
        } catch {
            NSLog("OpenCluely whisper: error %@", String(describing: error))
            return ""
        }
    }
}

/// Accumulates samples and yields fixed-size overlapping windows. Keeps a tail
/// so audio is never dropped while whisper is busy.
private actor SampleStore {
    private var buffer: [Float] = []
    private let windowSamples: Int
    private let hopSamples: Int

    init(windowSamples: Int, hopSamples: Int) {
        self.windowSamples = windowSamples
        self.hopSamples = hopSamples
    }

    /// Append new audio; return the next window to transcribe if ready, else nil.
    func append(_ pcm: [Float]) -> [Float]? {
        buffer.append(contentsOf: pcm)
        guard buffer.count >= windowSamples else { return nil }
        let window = Array(buffer.prefix(windowSamples))
        // Advance by hop, keeping the overlap tail for the next window.
        buffer.removeFirst(min(hopSamples, buffer.count))
        return window
    }
}
