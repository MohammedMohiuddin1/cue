//
//  PermissionsManager.swift
//  cluelyopen
//
//  Checks and helps request the two macOS permissions OpenCluely needs:
//  Screen Recording (system audio + screen OCR/screenshot) and Accessibility
//  (global hotkeys). Everything stays local; these just gate OS capabilities.
//

import AppKit
import CoreGraphics
import ApplicationServices

final class PermissionsManager {
    /// Screen Recording — required for system-audio capture and screen reading.
    var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Accessibility — required for global hotkeys.
    var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Prompt for Screen Recording (shows the system dialog on first call).
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    /// Prompt for Accessibility (shows the system dialog).
    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
