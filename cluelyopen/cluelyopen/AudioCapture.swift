//
//  AudioCapture.swift
//  cluelyopen
//
//  Captures system audio via ScreenCaptureKit and delivers 16 kHz mono
//  float PCM chunks (converting from SCK's native format with AVAudioConverter).
//  Requires the Screen Recording permission (system audio is delivered under it).
//

import Foundation
import ScreenCaptureKit
import AVFoundation

final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var onPCM: (([Float]) -> Void)?

    // Lazily-built converter to 16 kHz mono Float32 (whisper's required format).
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000,
                                             channels: 1,
                                             interleaved: false)!
    private var chunkCounter = 0

    func start(onPCM: @escaping ([Float]) -> Void) async throws {
        self.onPCM = onPCM

        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "OpenCluely", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No display available for capture."])
        }
        // Exclude our own app so we never capture our own sounds/window.
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        // Audio-only capture: capture system audio but keep the video stream at
        // the smallest possible size and lowest frame rate, and DON'T register a
        // screen output. Capturing display video can dim DRM-protected playback
        // (e.g. streaming sites) and is unnecessary — we only need audio.
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        // Only the audio output is registered — no screen output means SCK stops
        // delivering (and we stop touching) video frames.
        try stream.addStreamOutput(self, type: .audio,
                                   sampleHandlerQueue: DispatchQueue(label: "opencluely.audio"))
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        stream?.stopCapture(completionHandler: { _ in })
        stream = nil
        onPCM = nil
        converter = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        guard let samples = convertToTargetPCM(sampleBuffer) else { return }

        chunkCounter += 1
        if chunkCounter % 25 == 0 {
            NSLog("OpenCluely audio chunk #%d: %d samples, level=%.4f",
                  chunkCounter, samples.count, Self.level(of: samples))
        }
        if !samples.isEmpty { onPCM?(samples) }
    }

    // MARK: - Conversion

    /// Convert an SCK audio CMSampleBuffer (native format) to 16 kHz mono Float.
    private func convertToTargetPCM(_ sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let inputPCM = Self.pcmBuffer(from: sampleBuffer) else { return nil }

        // Build (or reuse) a converter from the input's format to our target.
        if converter == nil || converter?.inputFormat != inputPCM.format {
            converter = AVAudioConverter(from: inputPCM.format, to: targetFormat)
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / inputPCM.format.sampleRate
        let capacity = AVAudioFrameCount(Double(inputPCM.frameLength) * ratio) + 1
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        var fed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true
            outStatus.pointee = .haveData
            return inputPCM
        }
        guard status != .error, error == nil,
              let channel = outBuffer.floatChannelData else { return nil }

        let count = Int(outBuffer.frameLength)
        guard count > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channel[0], count: count))
    }

    /// Wrap a CMSampleBuffer's audio into an AVAudioPCMBuffer in its native format.
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return nil }
        let format = AVAudioFormat(streamDescription: asbd)
        guard let format else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames

        let audioBufferList = pcm.mutableAudioBufferList
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: audioBufferList
        )
        guard status == noErr else { return nil }
        return pcm
    }

    /// RMS level (0…1-ish) of a chunk, used to confirm audio is flowing.
    static func level(of pcm: [Float]) -> Float {
        guard !pcm.isEmpty else { return 0 }
        let sumSq = pcm.reduce(Float(0)) { $0 + $1 * $1 }
        return (sumSq / Float(pcm.count)).squareRoot()
    }
}
