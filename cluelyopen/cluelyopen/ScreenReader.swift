//
//  ScreenReader.swift
//  cluelyopen
//
//  Captures the current display and runs on-device OCR (Apple Vision) so the
//  AI can answer a coding/technical question that's visible on screen.
//  Fully local — Vision runs on-device, no network.
//

import Foundation
import ScreenCaptureKit
import Vision
import CoreGraphics

enum ScreenReaderError: Error, LocalizedError {
    case noDisplay
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display available to read."
        case .captureFailed: return "Couldn't capture the screen."
        }
    }
}

final class ScreenReader {
    /// Capture the main display and return the recognized text (top-to-bottom).
    func readScreen() async throws -> String {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw ScreenReaderError.noDisplay }

        // Exclude our own overlay so we OCR what's underneath, not our own UI.
        let ourApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter: SCContentFilter
        if let ourApp {
            filter = SCContentFilter(display: display, excludingApplications: [ourApp], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }

        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                 configuration: config)
        return try Self.recognizeText(in: cgImage)
    }

    /// Run Vision text recognition and join results in reading order.
    private static func recognizeText(in cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        // Sort roughly top-to-bottom (Vision's origin is bottom-left, so larger
        // minY is higher on screen).
        let lines = observations
            .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
