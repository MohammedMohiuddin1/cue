//
//  WhisperTranscriber.swift
//  cluelyopen
//
//  Streaming local speech-to-text using bundled whisper.cpp (via SwiftWhisper),
//  Core ML accelerated.
//
//  Streaming design: audio is appended continuously. A worker transcribes the
//  most recent ~7s of audio every time ~1.5s of new audio has arrived, then
//  emits only the words that are NEW compared to the previous run (prefix
//  diffing). This makes text appear ~1.5s after speech instead of waiting for a
//  full fixed window, while a rolling context keeps phrases coherent.
//

import Foundation
import SwiftWhisper
internal import whisper_cpp

final class WhisperTranscriber: Transcriber {
    private let whisper: Whisper
    private let store = StreamStore(
        contextSamples: 16_000 * 7,   // transcribe up to the last 7s
        triggerSamples: 16_000 * 3 / 2 // run when ~1.5s of new audio arrived
    )
    private var worker: Task<Void, Never>?
    private let onText: (String) -> Void
    private var lastEmitted = ""      // last full transcript of the rolling window

    init(modelURL: URL, onText: @escaping (String) -> Void) {
        let params = WhisperParams(strategy: .greedy)
        params.language = .english
        params.translate = false
        params.no_context = true
        params.suppress_blank = true
        self.whisper = Whisper(fromFileURL: modelURL, withParams: params)
        self.onText = onText
        startWorker()
    }

    deinit { worker?.cancel() }

    /// Called per audio chunk from capture; just buffers.
    func transcribe(_ pcm: [Float]) async -> String {
        await store.append(pcm)
        return ""
    }

    private func startWorker() {
        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let (window, isReset) = await self.store.nextWindow()
                if isReset { self.lastEmitted = "" }
                do {
                    let segments = try await self.whisper.transcribe(audioFrames: window)
                    let full = segments.map(\.text).joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let newText = Self.newSuffix(previous: self.lastEmitted, current: full)
                    self.lastEmitted = full
                    if !newText.isEmpty {
                        NSLog("OpenCluely whisper +\"%@\"", newText)
                        await MainActor.run { self.onText(newText) }
                    }
                } catch {
                    NSLog("OpenCluely whisper error %@", String(describing: error))
                }
            }
        }
    }

    /// Return the part of `current` that extends `previous` (word-level), so we
    /// only emit newly-transcribed words rather than re-emitting the whole window.
    private static func newSuffix(previous: String, current: String) -> String {
        guard !previous.isEmpty else { return current }
        let prevWords = previous.split(separator: " ")
        let curWords = current.split(separator: " ")
        // Find how many leading words still match; emit the rest.
        var i = 0
        while i < prevWords.count && i < curWords.count && prevWords[i] == curWords[i] { i += 1 }
        let tail = curWords[min(i, curWords.count)...]
        return tail.joined(separator: " ")
    }
}

/// Continuous store: keeps a rolling context window and signals the worker when
/// enough new audio has arrived. When the buffer would grow past the context
/// length, it slides forward and flags a reset so the diff baseline is cleared.
private actor StreamStore {
    private var buffer: [Float] = []
    private var newSinceLastWindow = 0
    private let contextSamples: Int
    private let triggerSamples: Int
    private var waiter: CheckedContinuation<([Float], Bool), Never>?

    init(contextSamples: Int, triggerSamples: Int) {
        self.contextSamples = contextSamples
        self.triggerSamples = triggerSamples
    }

    func append(_ pcm: [Float]) {
        buffer.append(contentsOf: pcm)
        newSinceLastWindow += pcm.count
        if let waiter, newSinceLastWindow >= triggerSamples {
            self.waiter = nil
            waiter.resume(returning: takeWindow())
        }
    }

    func nextWindow() async -> ([Float], Bool) {
        if newSinceLastWindow >= triggerSamples {
            return takeWindow()
        }
        return await withCheckedContinuation { cont in self.waiter = cont }
    }

    /// Returns (window, didReset). Slides the buffer when it exceeds the context
    /// length; a slide resets the diff baseline in the worker.
    private func takeWindow() -> ([Float], Bool) {
        newSinceLastWindow = 0
        var didReset = false
        if buffer.count > contextSamples {
            buffer.removeFirst(buffer.count - contextSamples)
            didReset = true
        }
        return (buffer, didReset)
    }
}
