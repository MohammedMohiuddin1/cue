//
//  WhisperTranscriber.swift
//  cluelyopen
//
//  Fully-local speech-to-text using bundled whisper.cpp (via SwiftWhisper).
//
//  Architecture: audio chunks are appended to a thread-safe buffer as they
//  arrive. A single dedicated worker loop pulls fixed windows and transcribes
//  them back-to-back, so no audio is dropped while whisper is busy. Results are
//  delivered via a callback (not the return value), decoupling capture rate from
//  transcription speed.
//

import Foundation
import SwiftWhisper

final class WhisperTranscriber: Transcriber {
    private let whisper: Whisper
    private let store: AudioAccumulator
    private var worker: Task<Void, Never>?
    private let onText: (String) -> Void

    private let windowSamples = 16_000 * 5   // 5s windows

    /// - Parameters:
    ///   - modelURL: ggml model path (e.g. ggml-small.en.bin)
    ///   - onText: called on the main actor with each newly transcribed phrase.
    init(modelURL: URL, onText: @escaping (String) -> Void) {
        let params = WhisperParams(strategy: .greedy)
        params.language = .english
        params.translate = false
        params.no_context = true
        params.suppress_blank = true
        self.whisper = Whisper(fromFileURL: modelURL, withParams: params)
        self.onText = onText
        self.store = AudioAccumulator(windowSamples: 16_000 * 5)
        startWorker()
    }

    deinit { worker?.cancel() }

    /// Called per audio chunk from capture. Just buffers; never blocks capture.
    func transcribe(_ pcm: [Float]) async -> String {
        await store.append(pcm)
        return ""   // results arrive via onText, not here
    }

    /// Dedicated loop: pull a window (waiting if not enough audio yet), run
    /// whisper, deliver text, repeat. Processes every window in order.
    private func startWorker() {
        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let window = await self.store.nextWindow()   // suspends until ready
                do {
                    let segments = try await self.whisper.transcribe(audioFrames: window)
                    let text = segments.map(\.text).joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        NSLog("OpenCluely whisper: \"%@\"", text)
                        await MainActor.run { self.onText(text) }
                    }
                } catch {
                    NSLog("OpenCluely whisper: error %@", String(describing: error))
                }
            }
        }
    }
}

/// Thread-safe accumulator that hands out fixed-size windows in order, waiting
/// (via a continuation) when not enough audio has arrived yet. No audio is lost.
private actor AudioAccumulator {
    private var buffer: [Float] = []
    private let windowSamples: Int
    private var waiter: CheckedContinuation<[Float], Never>?

    init(windowSamples: Int) { self.windowSamples = windowSamples }

    func append(_ pcm: [Float]) {
        buffer.append(contentsOf: pcm)
        // If a worker is waiting and we now have a full window, resume it.
        if let waiter, buffer.count >= windowSamples {
            self.waiter = nil
            waiter.resume(returning: takeWindow())
        }
    }

    /// Returns the next full window, suspending until enough audio exists.
    func nextWindow() async -> [Float] {
        if buffer.count >= windowSamples {
            return takeWindow()
        }
        return await withCheckedContinuation { cont in
            self.waiter = cont
        }
    }

    private func takeWindow() -> [Float] {
        let window = Array(buffer.prefix(windowSamples))
        buffer.removeFirst(min(windowSamples, buffer.count))
        return window
    }
}
