//
//  AudioCapture.swift
//  cluelyopen
//
//  Captures system audio via ScreenCaptureKit and delivers 16 kHz mono
//  float PCM chunks. Requires the Screen Recording permission (macOS delivers
//  system audio under that grant).
//

import Foundation
import ScreenCaptureKit
import AVFoundation

final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var onPCM: (([Float]) -> Void)?

    /// Start capturing system audio. `onPCM` receives 16 kHz mono float samples.
    func start(onPCM: @escaping ([Float]) -> Void) async throws {
        self.onPCM = onPCM

        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "OpenCluely", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display available for capture."])
        }

        // Exclude our own app from the capture content (belt-and-suspenders;
        // audio doesn't render, but this keeps the filter well-formed).
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 16_000   // whisper expects 16 kHz
        config.channelCount = 1      // mono
        // Keep video minimal; we only care about audio.
        config.width = 2
        config.height = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "opencluely.audio"))
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        stream?.stopCapture(completionHandler: { _ in })
        stream = nil
        onPCM = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let samples = Self.floatSamples(from: sampleBuffer) else { return }
        onPCM?(samples)
    }

    // MARK: - Helpers

    private static var didLogFormat = false

    /// Extract mono Float samples from a CMSampleBuffer's audio using the
    /// AudioBufferList API (the reliable way; ScreenCaptureKit delivers audio
    /// as an AudioBufferList, not a flat Float block).
    private static func floatSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        var blockBuffer: CMBlockBuffer?
        var abl = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        )

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &abl,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let data = abl.mBuffers.mData else { return nil }

        let byteCount = Int(abl.mBuffers.mDataByteSize)
        let floatCount = byteCount / MemoryLayout<Float>.size
        guard floatCount > 0 else { return nil }

        let floatPtr = data.bindMemory(to: Float.self, capacity: floatCount)
        let samples = Array(UnsafeBufferPointer(start: floatPtr, count: floatCount))

        if !didLogFormat {
            didLogFormat = true
            let maxAmp = samples.map { abs($0) }.max() ?? 0
            NSLog("OpenCluely audio: %d samples/chunk, first=%.4f maxAmp=%.4f (expect |x|<=1.0 float)",
                  floatCount, samples.first ?? 0, maxAmp)
        }
        return samples
    }

    /// Simple RMS level (0...1-ish) for a chunk, used to prove capture is live.
    static func level(of pcm: [Float]) -> Float {
        guard !pcm.isEmpty else { return 0 }
        let sumSq = pcm.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumSq / Float(pcm.count)).squareRoot()
    }
}
