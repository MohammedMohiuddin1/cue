//
//  WhisperTranscriber.swift
//  cluelyopen
//
//  Fully-local speech-to-text using bundled whisper.cpp (via SwiftWhisper).
//  Buffers incoming PCM until it has ~5 seconds, then transcribes that batch
//  so results are coherent phrases rather than word fragments.
//

import Foundation
import SwiftWhisper

/// Wraps SwiftWhisper's `Whisper` behind our `Transcriber` protocol.
/// Thread-safety: `transcribe(_:)` may be called from multiple tasks; access to
/// the sample buffer is serialized with an actor.
final class WhisperTranscriber: Transcriber {
    private let whisper: Whisper
    private let batcher = SampleBatcher(minSamples: 16_000 * 5) // ~5s at 16 kHz

    /// - Parameter modelURL: path to a ggml whisper model, e.g. ggml-base.en.bin
    init(modelURL: URL) {
        self.whisper = Whisper(fromFileURL: modelURL)
    }

    func transcribe(_ pcm: [Float]) async -> String {
        // Accumulate; only run whisper once we have enough audio.
        guard let batch = await batcher.add(pcm) else { return "" }
        NSLog("OpenCluely whisper: transcribing batch of %d samples (~%.1fs)",
              batch.count, Double(batch.count) / 16_000.0)
        do {
            let segments = try await whisper.transcribe(audioFrames: batch)
            let text = segments.map(\.text).joined()
            NSLog("OpenCluely whisper: got %d segments, text=\"%@\"", segments.count, text)
            return text
        } catch {
            NSLog("OpenCluely whisper: transcribe error: %@", String(describing: error))
            return ""
        }
    }
}

/// Serializes appends and hands back a full batch once the threshold is reached.
private actor SampleBatcher {
    private var buffer: [Float] = []
    private let minSamples: Int

    init(minSamples: Int) { self.minSamples = minSamples }

    /// Returns a batch to transcribe once enough audio has accumulated, else nil.
    func add(_ pcm: [Float]) -> [Float]? {
        buffer.append(contentsOf: pcm)
        guard buffer.count >= minSamples else { return nil }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)
        return batch
    }
}
